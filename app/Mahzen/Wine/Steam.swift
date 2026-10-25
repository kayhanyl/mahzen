import Foundation

struct SteamGame: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    var headerURL: URL { URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/header.jpg")! }
}

enum Steam {
    static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!
    /// Steamworks Common Redistributables: installed alongside games, not a game itself.
    private static let hiddenApps: Set<Int> = [228980]

    /// steamwebhelper crashes under non-UTF-8 or Turkish locales, and CEF's sandbox needs
    /// kernel calls Wine doesn't have. Games started from Steam inherit this too.
    static let environment = [
        "LC_ALL": "en_US.UTF-8",
        "LANG": "en_US.UTF-8",
        "STEAM_DISABLE_CEF_SANDBOX": "1",
        "CEF_DISABLE_SANDBOX": "1",
    ]

    static func downloadInstaller() async throws -> URL {
        let destination = Paths.cache.appending(path: "SteamSetup.exe")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let (temp, response) = try await URLSession.shared.download(from: installerURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WineError.download("Steam kurulum dosyası") }
        Paths.ensure(Paths.cache)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    /// Installed games, read from Steam's appmanifest_<appid>.acf files.
    static func games(in bottle: Bottle) -> [SteamGame] {
        let steamapps = bottle.steamExe.deletingLastPathComponent().appending(path: "steamapps")
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { url -> SteamGame? in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let appid = text.firstMatch(of: #/"appid"\s+"(\d+)"/#).flatMap({ Int($0.1) }),
                      let name = text.firstMatch(of: #/"name"\s+"([^"]*)"/#).map({ String($0.1) }),
                      !hiddenApps.contains(appid) else { return nil }
                return SteamGame(id: appid, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
