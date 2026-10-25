import Foundation

/// Where Mahzen keeps its data. Engines are produced by `engine/package.sh`.
enum Paths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Mahzen", directoryHint: .isDirectory)
    static let engines = support.appending(path: "Engines", directoryHint: .isDirectory)
    static let bottles = support.appending(path: "Bottles", directoryHint: .isDirectory)
    static let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "Mahzen", directoryHint: .isDirectory)

    static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
