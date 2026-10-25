import SwiftUI

struct BottleSettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let original: Bottle
    @State private var draft: Bottle

    init(bottle: Bottle) {
        original = bottle
        _draft = State(initialValue: bottle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    TextField("Name", text: $draft.name)
                    Picker("Windows version", selection: $draft.windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Picker("Graphics layer", selection: $draft.backend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    if !store.hasEngine(family: draft.engineFamily, backend: draft.backend) {
                        Label("No engine is installed for this layer.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Toggle("Retina mode", isOn: $draft.retinaMode)
                    Toggle("Metal HUD (FPS counter)", isOn: $draft.metalHUD)
                } header: {
                    Text("Graphics")
                } footer: {
                    Text("\(draft.backend.detail) Retina mode is sharper but heavier; keep it off in slow games.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("MSync", isOn: $draft.msync)
                    Toggle("Verbose logging", isOn: $draft.verboseLog)
                } header: {
                    Text("Performance and Debugging")
                } footer: {
                    Text("MSync handles Windows synchronization in the macOS kernel and speeds up most games. Verbose logging helps when tracking down a problem but can slow programs down.")
                        .foregroundStyle(.secondary)
                }

                Section("Steam") {
                    TextField("Launch arguments", text: $draft.steamArguments)
                        .font(.body.monospaced())
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = draft
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                    Task { await store.save(saved, previous: original) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
    }
}
