import AppKit
import Foundation

@MainActor @Observable
final class Store {
    var engines: [Engine] = []
    var bottles: [Bottle] = []
    var selection: Bottle.ID?
    /// Live `wine` processes started from the app, per bottle.
    var running: [Bottle.ID: Int] = [:]
    /// What a bottle is busy with ("Installing Steam…"), shown instead of its actions.
    var busy: [Bottle.ID: String] = [:]
    /// .exe/.msi files opened from Finder, waiting for the user to pick a bottle.
    var pendingOpen: [URL] = []
    var errorMessage: String?
    var showingNewBottle = false
    /// Bumped after anything that changes a prefix on disk, so views rescan it.
    var revision = 0

    init() {
        Paths.ensure(Paths.engines)
        Paths.ensure(Paths.bottles)
        reload()
    }

    func reload() {
        engines = Engine.scan()
        bottles = Bottle.loadAll()
        if let selection, !bottles.contains(where: { $0.id == selection }) { self.selection = nil }
        if selection == nil { selection = bottles.first?.id }
        revision += 1
    }

    var selectedBottle: Bottle? { bottles.first { $0.id == selection } }
    var families: [String] { Array(Set(engines.map(\.family))).sorted() }

    func hasEngine(family: String, backend: GraphicsBackend) -> Bool {
        engines.contains { $0.family == family && $0.backend == backend }
    }

    func isRunning(_ bottle: Bottle) -> Bool { running[bottle.id, default: 0] > 0 }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func runner(for bottle: Bottle) throws -> WineRunner {
        try WineRunner(bottle: bottle, engines: engines)
    }

    /// Runs `work` while the bottle shows `status`; errors end up in the alert.
    @discardableResult
    private func perform(_ bottle: Bottle, _ status: String, _ work: () async throws -> Void) async -> Bool {
        busy[bottle.id] = status
        defer {
            busy[bottle.id] = nil
            revision += 1
        }
        do {
            try await work()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Bottles

    func createBottle(name: String, family: String, backend: GraphicsBackend, windowsVersion: WindowsVersion) async {
        let bottle = Bottle(name: name, engineFamily: family, backend: backend, windowsVersion: windowsVersion)
        do {
            try bottle.save()
        } catch {
            report(error)
            return
        }
        bottles.append(bottle)
        bottles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selection = bottle.id
        await initialize(bottle)
    }

    func initialize(_ bottle: Bottle) async {
        await perform(bottle, String(localized: "Setting up the bottle… (the first time can take a minute)")) {
            try await runner(for: bottle).initialize()
        }
    }

    func update(_ bottle: Bottle) {
        do {
            try bottle.save()
        } catch {
            report(error)
            return
        }
        if let i = bottles.firstIndex(where: { $0.id == bottle.id }) { bottles[i] = bottle }
    }

    /// Saves settings and pushes the ones that live in the Wine registry into the prefix.
    func save(_ bottle: Bottle, previous: Bottle) async {
        update(bottle)
        guard bottle.isInitialized else { return }
        let needsRegistry = bottle.windowsVersion != previous.windowsVersion || bottle.retinaMode != previous.retinaMode
        let backendChanged = bottle.backend != previous.backend
        guard needsRegistry || backendChanged else { return }
        await perform(bottle, String(localized: "Applying settings…")) {
            // Processes from the old engine variant would keep its DLLs loaded.
            if backendChanged, let old = try? runner(for: previous) { await old.stop() }
            let r = try runner(for: bottle)
            if bottle.windowsVersion != previous.windowsVersion { try await r.setWindowsVersion(bottle.windowsVersion) }
            if bottle.retinaMode != previous.retinaMode { try await r.setRetinaMode(bottle.retinaMode) }
        }
    }

    func delete(_ bottle: Bottle) async {
        if let r = try? runner(for: bottle) { await r.stop() }
        do {
            try FileManager.default.removeItem(at: bottle.directory)
        } catch {
            report(error)
        }
        bottles.removeAll { $0.id == bottle.id }
        running[bottle.id] = nil
        if selection == bottle.id { selection = bottles.first?.id }
    }

    func stop(_ bottle: Bottle) async {
        await perform(bottle, String(localized: "Stopping…")) {
            try await runner(for: bottle).stop()
        }
        running[bottle.id] = nil
    }

    // MARK: - Launching

    private func launch(_ bottle: Bottle, _ arguments: [String], in directory: URL?, logName: String,
                        extraEnvironment: [String: String] = [:]) {
        let id = bottle.id
        do {
            try runner(for: bottle).launch(arguments, in: directory, logName: logName,
                                           extraEnvironment: extraEnvironment) { _ in
                Task { @MainActor in self.processEnded(id) }
            }
            running[id, default: 0] += 1
        } catch {
            report(error)
        }
    }

    private func processEnded(_ id: Bottle.ID) {
        running[id] = max(0, running[id, default: 0] - 1)
        revision += 1
    }

    /// Runs an .exe or .msi that lives anywhere on the Mac.
    func run(_ file: URL, in bottle: Bottle) {
        let name = file.deletingPathExtension().lastPathComponent
        if file.pathExtension.lowercased() == "msi" {
            launch(bottle, ["msiexec", "/i", file.path], in: file.deletingLastPathComponent(), logName: name)
        } else {
            launch(bottle, [file.path], in: file.deletingLastPathComponent(), logName: name)
        }
    }

    func run(_ program: Program, in bottle: Bottle) {
        launch(bottle, [program.path] + splitArguments(program.arguments),
               in: program.url.deletingLastPathComponent(), logName: program.name)
    }

    /// Built-in Wine programs: winecfg, regedit, taskmgr, explorer…
    func runTool(_ tool: String, in bottle: Bottle) {
        launch(bottle, [tool], in: nil, logName: tool)
    }

    func openPending(in bottle: Bottle) {
        for url in pendingOpen { run(url, in: bottle) }
        pendingOpen = []
    }

    // MARK: - Programs

    func pin(_ program: Program, in bottle: Bottle) {
        var b = bottle
        guard !b.programs.contains(where: { $0.path == program.path }) else { return }
        b.programs.append(program)
        update(b)
    }

    func unpin(_ program: Program, in bottle: Bottle) {
        var b = bottle
        b.programs.removeAll { $0.id == program.id }
        update(b)
    }

    // MARK: - Steam

    func installSteam(in bottle: Bottle) async {
        await perform(bottle, String(localized: "Downloading Steam…")) {
            let setup = try await Steam.downloadInstaller()
            busy[bottle.id] = String(localized: "Installing Steam…")
            // The installer starts Steam by itself when it finishes, so the DLL setup and
            // environment have to be in place before it runs, not before our first launch.
            let r = try runner(for: bottle)
            try await r.prepareSteam()
            let code = try await r.run([setup.path, "/S"], in: Paths.cache, logName: "steam-setup",
                                       extraEnvironment: Steam.environment)
            guard bottle.hasSteam else { throw WineError.failed(String(localized: "Steam installation"), code) }
        }
    }

    func launchSteam(in bottle: Bottle) {
        startSteam(bottle, splitArguments(bottle.steamArguments), logName: "steam")
    }

    func launch(_ game: SteamGame, in bottle: Bottle) {
        startSteam(bottle, splitArguments(bottle.steamArguments) + ["-applaunch", String(game.id)], logName: game.name)
    }

    /// Re-applies the Steam DLL setup every time: the engine (and its DXVK) can change
    /// between launches, and a prefix update can put Wine's placeholders back.
    private func startSteam(_ bottle: Bottle, _ arguments: [String], logName: String) {
        Task {
            guard await perform(bottle, String(localized: "Preparing Steam…"), {
                try await runner(for: bottle).prepareSteam()
            }) else { return }
            launch(bottle, [bottle.steamExe.path] + arguments, in: bottle.steamExe.deletingLastPathComponent(),
                   logName: logName, extraEnvironment: Steam.environment)
        }
    }

    // MARK: - Finder

    func reveal(_ url: URL) {
        Paths.ensure(url)
        NSWorkspace.shared.open(url)
    }
}
