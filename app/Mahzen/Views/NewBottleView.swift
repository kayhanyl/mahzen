import SwiftUI

struct NewBottleView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Oyunlar"
    @State private var family = ""
    @State private var backend: GraphicsBackend = .dxmt
    @State private var windowsVersion: WindowsVersion = .win10

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Ad", text: $name)
                    if store.families.count > 1 {
                        Picker("Motor", selection: $family) {
                            ForEach(store.families, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("Grafik katmanı", selection: $backend) {
                        ForEach(GraphicsBackend.allCases) { b in
                            Text(b.title).tag(b)
                        }
                    }
                    Picker("Windows sürümü", selection: $windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Yeni Bottle")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(backend.detail)
                        if !store.hasEngine(family: family, backend: backend) {
                            Label("Bu katman için motor kurulu değil.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Oluştur") {
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
