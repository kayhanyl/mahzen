import Foundation

/// How DirectX calls reach the GPU. Each backend is a separate engine build (see package.sh).
enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case d3dmetal, dxmt, wined3d

    var id: String { rawValue }

    var title: String {
        switch self {
        case .d3dmetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .wined3d: "WineD3D"
        }
    }

    var detail: String {
        switch self {
        case .d3dmetal: String(localized: "DirectX 11/12 → Metal (Apple). For DirectX 12 games; some DX11 games crash on it (e.g. Kenshi).")
        case .dxmt: String(localized: "DirectX 10/11 → Metal (open source). Recommended for DirectX 11 games.")
        case .wined3d: String(localized: "DirectX → OpenGL. Slow but the most compatible; for older games.")
        }
    }
}

/// One installed engine variant, described by the engine.json that package.sh writes.
struct Engine: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let wineVersion: String
    let backend: GraphicsBackend
    let root: URL

    /// "cx26.3" for "cx26.3-d3dmetal": bottles pick a family, the backend picks the variant.
    var family: String { String(id.dropLast(backend.rawValue.count + 1)) }
    var wine: URL { root.appending(path: "bin/wine") }
    var wineserver: URL { root.appending(path: "bin/wineserver") }

    private struct Manifest: Decodable {
        let id, name, wineVersion: String
        let backend: GraphicsBackend
    }

    static func scan() -> [Engine] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Paths.engines, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "engine.json")),
                  let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
            return Engine(id: m.id, name: m.name, wineVersion: m.wineVersion, backend: m.backend, root: dir)
        }
        .sorted { $0.id < $1.id }
    }
}
