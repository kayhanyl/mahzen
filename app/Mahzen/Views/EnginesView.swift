import SwiftUI

/// Settings window: the engine variants found in Application Support.
struct EnginesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.engines.isEmpty {
                ContentUnavailableView("No Engines", systemImage: "shippingbox",
                                       description: Text("engine/package.sh installs engines into \(Paths.engines.path)."))
            } else {
                Form {
                    ForEach(store.families, id: \.self) { family in
                        Section(family) {
                            ForEach(store.engines.filter { $0.family == family }) { engine in
                                LabeledContent {
                                    Text(engine.wineVersion).foregroundStyle(.secondary)
                                } label: {
                                    Text(engine.backend.title)
                                    Text(engine.backend.detail)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button("Reload", systemImage: "arrow.clockwise") { store.reload() }
                Spacer()
                Button("Open Folder", systemImage: "folder") { store.reveal(Paths.engines) }
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
    }
}
