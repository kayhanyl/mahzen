import Foundation

enum WineError: LocalizedError {
    case engineMissing(String)
    case failed(String, Int32)
    case download(String)

    var errorDescription: String? {
        switch self {
        case .engineMissing(let id): String(localized: "The “\(id)” engine isn’t installed. Install it with engine/package.sh.")
        case .failed(let what, let code): String(localized: "\(what) failed (exit code \(code)). See the logs for details.")
        case .download(let what): String(localized: "Couldn’t download \(what).")
        }
    }
}

/// Builds and starts Wine processes for one bottle.
struct WineRunner: Sendable {
    let engine: Engine
    let bottle: Bottle

    static func engineID(for bottle: Bottle) -> String { "\(bottle.engineFamily)-\(bottle.backend.rawValue)" }

    init(bottle: Bottle, engines: [Engine]) throws {
        let id = Self.engineID(for: bottle)
        guard let engine = engines.first(where: { $0.id == id }) else { throw WineError.engineMissing(id) }
        self.engine = engine
        self.bottle = bottle
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefix.path
        env["WINEDEBUG"] = bottle.verboseLog ? "fixme-all,err+all" : "-all"
        // Keeps Wine from writing .desktop files and menu entries for every installer.
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"
        env["CX_ACTIVE_GRAPHICS_BACKEND"] = bottle.backend.rawValue
        env["DYLD_FALLBACK_LIBRARY_PATH"] = engine.root.appending(path: "lib").path + ":/usr/lib"
        if bottle.msync { env["WINEMSYNC"] = "1" }
        if bottle.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }

    /// Starts `wine <arguments>` and returns immediately; `onExit` fires when it ends.
    func launch(_ arguments: [String], in directory: URL? = nil, logName: String,
                extraEnvironment: [String: String] = [:],
                onExit: @escaping @Sendable (Int32) -> Void = { _ in }) throws {
        let job = try makeJob(engine.wine, arguments, in: directory, logName: logName)
        job.process.environment?.merge(extraEnvironment) { _, new in new }
        job.process.terminationHandler = { process in
            try? job.log?.close()
            onExit(process.terminationStatus)
        }
        try job.process.run()
    }

    /// Runs `wine <arguments>` and waits for it to finish.
    @discardableResult
    func run(_ arguments: [String], in directory: URL? = nil, logName: String,
             extraEnvironment: [String: String] = [:]) async throws -> Int32 {
        try await wait(engine.wine, arguments, in: directory, logName: logName, extraEnvironment: extraEnvironment)
    }

    /// Creates the prefix (fake C: drive, registry) and applies the bottle's settings.
    func initialize() async throws {
        Paths.ensure(bottle.prefix)
        let code = try await run(["wineboot", "--init"], logName: "wineboot")
        guard code == 0 else { throw WineError.failed(String(localized: "Setting up the bottle"), code) }
        try await setWindowsVersion(bottle.windowsVersion)
        if bottle.retinaMode { try await setRetinaMode(true) }
        // The registry (system.reg, which isInitialized checks) is only flushed when wineserver exits.
        _ = try? await wait(engine.wineserver, ["-w"], in: nil, logName: nil)
    }

    func setWindowsVersion(_ version: WindowsVersion) async throws {
        let code = try await run(["winecfg", "-v", version.rawValue], logName: "winecfg")
        guard code == 0 else { throw WineError.failed(String(localized: "Setting the Windows version"), code) }
    }

    func setRetinaMode(_ on: Bool) async throws {
        let code = try await run(["reg", "add", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode",
                                  "/t", "REG_SZ", "/d", on ? "y" : "n", "/f"], logName: "retina")
        guard code == 0 else { throw WineError.failed(String(localized: "Setting Retina mode"), code) }
    }

    /// Steam draws its UI with Chromium, which can't present through D3DMetal or DXMT.
    /// Its own processes get the engine's DXVK as native DLLs through per-exe AppDefaults,
    /// so games Steam starts still use the bottle's backend.
    func prepareSteam() async throws {
        let fm = FileManager.default
        let dxvk = engine.root.appending(path: "lib/dxvk")
        for (arch, dir) in [("x64", "system32"), ("x32", "syswow64")] {
            for dll in ["dxgi.dll", "d3d11.dll"] {
                let src = dxvk.appending(path: "\(arch)/\(dll)")
                let dst = bottle.driveC.appending(path: "windows/\(dir)/\(dll)")
                guard fm.fileExists(atPath: src.path) else { continue }
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: src, to: dst)
            }
        }

        // d3d12/nvapi/nvngx are D3DMetal's: Chromium probes D3D12 at startup and hangs when
        // it gets DXVK's adapter. vulkan-1 must be Wine's, not the loader Chromium ships.
        let overrides = """
            "dxgi"="native"
            "d3d11"="native"
            "vulkan-1"="builtin"
            "d3d12"=""
            "nvapi64"=""
            "nvngx"=""
            """
        let exes = ["steam.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui64.exe", "GameOverlayUI.exe"]
        let reg = "REGEDIT4\n\n" + exes.map {
            "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\($0)\\DllOverrides]\n\(overrides)\n"
        }.joined(separator: "\n")
        let file = bottle.directory.appending(path: "steam-overrides.reg")
        try reg.write(to: file, atomically: true, encoding: .utf8)
        let code = try await run(["regedit", "/S", file.path], logName: "steam-overrides")
        guard code == 0 else { throw WineError.failed(String(localized: "Steam setup"), code) }
    }

    /// Kills every Windows process in the bottle.
    func stop() async {
        _ = try? await wait(engine.wineserver, ["-k"], in: nil, logName: nil)
    }

    /// Wine only finds a builtin DLL through a placeholder in system32. Prefixes get
    /// placeholders for Wine's own DLLs, but not for DXMT's winemetal.dll, so without
    /// this its d3d11/dxgi fail to load.
    private func installBackendPlaceholders() {
        guard engine.backend == .dxmt else { return }
        let fm = FileManager.default
        for (arch, dir) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
            let src = engine.root.appending(path: "lib/wine/\(arch)/winemetal.dll")
            let dst = bottle.driveC.appending(path: "windows/\(dir)/winemetal.dll")
            guard fm.fileExists(atPath: src.path), !fm.contentsEqual(atPath: src.path, andPath: dst.path) else { continue }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
    }

    // MARK: - Process plumbing

    private struct Job {
        let process: Process
        let log: FileHandle?
    }

    private func wait(_ executable: URL, _ arguments: [String], in directory: URL?, logName: String?,
                      extraEnvironment: [String: String] = [:]) async throws -> Int32 {
        let job = try makeJob(executable, arguments, in: directory, logName: logName)
        job.process.environment?.merge(extraEnvironment) { _, new in new }
        return try await withCheckedThrowingContinuation { continuation in
            job.process.terminationHandler = { process in
                try? job.log?.close()
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try job.process.run()
            } catch {
                job.process.terminationHandler = nil
                try? job.log?.close()
                continuation.resume(throwing: error)
            }
        }
    }

    /// Wine is started directly, never through /bin/sh: SIP strips DYLD_* from protected binaries.
    private func makeJob(_ executable: URL, _ arguments: [String], in directory: URL?, logName: String?) throws -> Job {
        if executable == engine.wine { installBackendPlaceholders() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory ?? bottle.directory
        process.standardInput = FileHandle.nullDevice

        guard let logName else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            return Job(process: process, log: nil)
        }

        Paths.ensure(bottle.logs)
        let url = bottle.logs.appending(path: "\(Self.timestamp())-\(Self.fileSafe(logName)).log")
        let header = """
            $ \(executable.lastPathComponent) \(arguments.joined(separator: " "))
            engine: \(engine.id) (\(engine.wineVersion))
            directory: \((directory ?? bottle.directory).path)


            """
        FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        process.standardOutput = handle
        process.standardError = handle
        return Job(process: process, log: handle)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }

    private static func fileSafe(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(60))
    }
}

/// Splits a command line the way a shell would for simple cases: spaces separate, quotes group.
func splitArguments(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    var inToken = false
    for ch in line {
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
        } else if ch == "\"" || ch == "'" {
            quote = ch
            inToken = true
        } else if ch.isWhitespace {
            if inToken { result.append(current); current = ""; inToken = false }
        } else {
            current.append(ch)
            inToken = true
        }
    }
    if inToken { result.append(current) }
    return result
}
