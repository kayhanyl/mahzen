import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("Bottles") {
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
                    Label("New Bottle", systemImage: "plus.circle.fill")
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
                    Label("Select a Bottle", systemImage: "wineglass")
                } description: {
                    if store.bottles.isEmpty {
                        Text("A bottle is a virtual C: drive that Windows programs are installed into. Create your first bottle.")
                    } else {
                        Text("Select a bottle on the left.")
                    }
                } actions: {
                    Button("New Bottle") { store.showingNewBottle = true }
                }
            }
        }
        .sheet(isPresented: $store.showingNewBottle) { NewBottleView() }
        .sheet(isPresented: Binding(get: { !store.pendingOpen.isEmpty }, set: { if !$0 { store.pendingOpen = [] } })) {
            OpenWithView()
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
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
                    .help("A program is running")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NoEnginesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("No Engine Installed", systemImage: "shippingbox")
        } description: {
            Text("""
                Mahzen runs Windows programs with a Wine engine you build yourself. \
                To build and install it, run these in the engine folder:
                fetch.sh → deps.sh → build-wine.sh → build-dxvk.sh → package.sh

                Engines are installed to:
                \(Paths.engines.path)
                """)
        } actions: {
            Button("Reload") { store.reload() }
                .keyboardShortcut("r")
            Button("Open Folder") { store.reveal(Paths.engines) }
        }
    }
}

/// Shown when an .exe/.msi is opened from Finder.
private struct OpenWithView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if store.pendingOpen.count == 1 {
                    Text("Which bottle should “\(store.pendingOpen[0].lastPathComponent)” run in?")
                } else {
                    Text("Which bottle should these \(store.pendingOpen.count) files run in?")
                }
            }
            .font(.headline)
            if store.bottles.isEmpty {
                Text("Create a bottle first.").foregroundStyle(.secondary)
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
                Button("Cancel", role: .cancel) { store.pendingOpen = [] }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
