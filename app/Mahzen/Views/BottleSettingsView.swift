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
                Section("Genel") {
                    TextField("Ad", text: $draft.name)
                    Picker("Windows sürümü", selection: $draft.windowsVersion) {
                        ForEach(WindowsVersion.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Picker("Grafik katmanı", selection: $draft.backend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    if !store.hasEngine(family: draft.engineFamily, backend: draft.backend) {
                        Label("Bu katman için motor kurulu değil.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Toggle("Retina modu", isOn: $draft.retinaMode)
                    Toggle("Metal HUD (FPS göstergesi)", isOn: $draft.metalHUD)
                } header: {
                    Text("Grafik")
                } footer: {
                    Text(draft.backend.detail + " Retina modu keskin ama daha ağırdır; yavaş oyunlarda kapalı tut.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("MSync", isOn: $draft.msync)
                    Toggle("Ayrıntılı log", isOn: $draft.verboseLog)
                } header: {
                    Text("Performans ve hata ayıklama")
                } footer: {
                    Text("MSync, Windows senkronizasyonunu macOS çekirdeğinde yapar ve çoğu oyunu hızlandırır. Ayrıntılı log sorun ararken işe yarar ama programları yavaşlatabilir.")
                        .foregroundStyle(.secondary)
                }

                Section("Steam") {
                    TextField("Başlatma argümanları", text: $draft.steamArguments)
                        .font(.body.monospaced())
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") {
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
