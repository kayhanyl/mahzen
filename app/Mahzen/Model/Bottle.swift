import Foundation

enum WindowsVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    case win11, win10, win81, win7, winxp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .win11: "Windows 11"
        case .win10: "Windows 10"
        case .win81: "Windows 8.1"
        case .win7: "Windows 7"
        case .winxp: "Windows XP"
        }
    }
}

/// A program the user pinned to a bottle.
struct Program: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Unix path of the .exe inside the prefix.
    var path: String
    var arguments: String = ""

    var url: URL { URL(filePath: path) }
}

/// A bottle is a Wine prefix (a fake C: drive with its own registry) plus its settings.
/// Stored as `Bottles/<id>/bottle.json` next to `Bottles/<id>/prefix`.
struct Bottle: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var engineFamily: String
    var backend: GraphicsBackend = .dxmt
    var windowsVersion: WindowsVersion = .win10
    var retinaMode = false
    var metalHUD = false
    var msync = true
    var verboseLog = false
    /// Extra steam.exe flags. Empty by default: -noverifyfiles skips the first client download.
    var steamArguments = ""
    var programs: [Program] = []

    var directory: URL { Paths.bottles.appending(path: id.uuidString, directoryHint: .isDirectory) }
    var prefix: URL { directory.appending(path: "prefix", directoryHint: .isDirectory) }
    var driveC: URL { prefix.appending(path: "drive_c", directoryHint: .isDirectory) }
    var logs: URL { directory.appending(path: "logs", directoryHint: .isDirectory) }
    var steamExe: URL { driveC.appending(path: "Program Files (x86)/Steam/steam.exe") }
    var hasSteam: Bool { FileManager.default.fileExists(atPath: steamExe.path) }
    var isInitialized: Bool { FileManager.default.fileExists(atPath: prefix.appending(path: "system.reg").path) }

    func save() throws {
        Paths.ensure(directory)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: directory.appending(path: "bottle.json"), options: .atomic)
    }

    static func loadAll() -> [Bottle] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Paths.bottles, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "bottle.json")) else { return nil }
            return try? JSONDecoder().decode(Bottle.self, from: data)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
