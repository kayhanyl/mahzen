import SwiftUI

struct NewBottleView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = String(localized: "Games", comment: "Default name for a new bottle")
    @State private var family = ""
    @State private var backend: GraphicsBackend = .dxmt
    @State private var windowsVersion: WindowsVersion = .win10

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if store.families.count > 1 {
                        Picker("Engine", selection: $family) {
                            ForEach(store.families, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("Graphics layer", selection: $backend) {
                        ForEach(GraphicsBackend.allCases) { b in
                            Text(b.title).tag(b)
                        }
                    }
                    Picker("Windows version", selection: $windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("New Bottle")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(backend.detail)
                        if !store.hasEngine(family: family, backend: backend) {
                            Label("No engine is installed for this layer.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let (name, family, backend, version) = (trimmedName, family, backend, windowsVersion)
                    Task { await store.createBottle(name: name, family: family, backend: backend, windowsVersion: version) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || !store.hasEngine(family: family, backend: backend))
            }
            .padding(16)
        }
        .frame(width: 460, height: 340)
        .onAppear {
            family = store.families.first ?? ""
            if !store.hasEngine(family: family, backend: backend),
               let available = GraphicsBackend.allCases.first(where: { store.hasEngine(family: family, backend: $0) }) {
                backend = available
            }
        }
    }
}
