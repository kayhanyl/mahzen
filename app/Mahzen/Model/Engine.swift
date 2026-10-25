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
        case .d3dmetal: "DirectX 11/12 → Metal (Apple). DirectX 12 oyunlar için; bazı DX11 oyunlarda çöküyor (ör. Kenshi)."
        case .dxmt: "DirectX 10/11 → Metal (açık kaynak). DirectX 11 oyunlar için önerilen."
        case .wined3d: "DirectX → OpenGL. Yavaş ama en uyumlu; eski oyunlar için."
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
