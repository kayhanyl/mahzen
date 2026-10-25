import Foundation

/// Finds launchable .exe files that installers left in Program Files.
enum ProgramScanner {
    private static let maxDepth = 3
    /// Steam has its own section; the rest ship with every fresh prefix.
    private static let skippedFolders: Set<String> = [
        "steam", "common files", "internet explorer", "windows media player", "windows nt", "windowspowershell",
    ]
    static func scan(_ bottle: Bottle) -> [Program] {
        let skippedNames = #/unins|setup|install|crash|redist|vc_|dxsetup|update|helper|report/#.ignoresCase()
        let roots = ["Program Files", "Program Files (x86)"].map { bottle.driveC.appending(path: $0, directoryHint: .isDirectory) }
        var found: [Program] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    if walker.level >= maxDepth || (walker.level == 1 && skippedFolders.contains(url.lastPathComponent.lowercased())) {
                        walker.skipDescendants()
                    }
                    continue
                }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                guard name.firstMatch(of: skippedNames) == nil else { continue }
                found.append(Program(name: name, path: url.path))
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
