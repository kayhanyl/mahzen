import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("Bottle'lar") {
                    ForEach(store.bottles) { bottle in
                        BottleRow(bottle: bottle).tag(bottle.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.showingNewBottle = true
                } label: {
                    Label("Yeni Bottle", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(store.engines.isEmpty)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            if store.engines.isEmpty {
                NoEnginesView()
            } else if let bottle = store.selectedBottle {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                ContentUnavailableView {
                    Label("Bottle seç", systemImage: "wineglass")
                } description: {
                    Text(store.bottles.isEmpty
                         ? "Bottle, Windows programlarının kurulduğu sanal bir C: sürücüsüdür. İlk bottle'ını oluştur."
                         : "Soldan bir bottle seç.")
                } actions: {
                    Button("Yeni Bottle") { store.showingNewBottle = true }
                }
            }
        }
        .sheet(isPresented: $store.showingNewBottle) { NewBottleView() }
        .sheet(isPresented: Binding(get: { !store.pendingOpen.isEmpty }, set: { if !$0 { store.pendingOpen = [] } })) {
            OpenWithView()
        }
        .alert("Bir sorun oluştu", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct BottleRow: View {
    @Environment(Store.self) private var store
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wineglass.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(bottle.name)
                Text("\(bottle.backend.title) · \(bottle.windowsVersion.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.busy[bottle.id] != nil {
                ProgressView().controlSize(.small)
            } else if store.isRunning(bottle) {
                Circle().fill(.green).frame(width: 8, height: 8)
                    .help("Çalışan program var")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NoEnginesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Motor kurulu değil", systemImage: "shippingbox")
        } description: {
            Text("""
                Mahzen, Windows programlarını kendi derlediği Wine motoruyla çalıştırır. \
                Motoru derleyip kurmak için engine klasöründe şunları çalıştır:
                fetch.sh → deps.sh → build-wine.sh → build-dxvk.sh → package.sh

                Motorlar şuraya kurulur:
                \(Paths.engines.path)
                """)
        } actions: {
            Button("Yenile") { store.reload() }
                .keyboardShortcut("r")
            Button("Klasörü Aç") { store.reveal(Paths.engines) }
        }
    }
}

/// Shown when an .exe/.msi is opened from Finder.
private struct OpenWithView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.pendingOpen.count == 1
                 ? "“\(store.pendingOpen[0].lastPathComponent)” hangi bottle'da çalışsın?"
                 : "\(store.pendingOpen.count) dosya hangi bottle'da çalışsın?")
                .font(.headline)
            if store.bottles.isEmpty {
                Text("Önce bir bottle oluşturmalısın.").foregroundStyle(.secondary)
            }
            ForEach(store.bottles) { bottle in
                Button {
                    store.openPending(in: bottle)
                    dismiss()
                } label: {
                    Label(bottle.name, systemImage: "wineglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.large)
                .disabled(!bottle.isInitialized)
            }
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { store.pendingOpen = [] }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
