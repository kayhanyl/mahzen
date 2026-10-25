import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    @Environment(Store.self) private var store
    let bottle: Bottle

    @State private var games: [SteamGame] = []
    @State private var discovered: [Program] = []
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var confirmDelete = false
    @State private var dropTargeted = false

    private static let runnableTypes: [UTType] = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let status = store.busy[bottle.id] {
                    banner {
                        ProgressView().controlSize(.small)
                        Text(status)
                    }
                } else if !bottle.isInitialized {
                    banner {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("This bottle hasn’t been set up yet.")
                        Spacer()
                        Button("Set Up") { Task { await store.initialize(bottle) } }
                    }
                } else {
                    steamSection
                    pinnedSection
                    discoveredSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(Label("Drop to Run", systemImage: "play.circle").font(.title2))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            run(urls)
        } isTargeted: { dropTargeted = $0 && bottle.isInitialized }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.runnableTypes) { result in
            if case .success(let url) = result { _ = run([url]) }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) { BottleSettingsView(bottle: bottle) }
        .sheet(isPresented: $showLogs) { LogView(bottle: bottle) }
        .confirmationDialog("Delete “\(bottle.name)”?", isPresented: $confirmDelete) {
            Button("Delete Bottle", role: .destructive) { Task { await store.delete(bottle) } }
        } message: {
            Text("All programs, games and saves in it are deleted permanently.")
        }
        .task(id: store.revision) { await rescan() }
        .navigationTitle(bottle.name)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name).font(.largeTitle.bold())
                HStack(spacing: 6) {
                    tag(bottle.engineFamily, "shippingbox")
                    tag(bottle.backend.title, "cpu")
                    tag(bottle.windowsVersion.title, "macwindow")
                    if store.isRunning(bottle) { tag(String(localized: "Running"), "circle.fill", tint: .green) }
                }
            }
        }
    }

    @ViewBuilder
    private var steamSection: some View {
        section("Steam", systemImage: "gamecontroller") {
            if bottle.hasSteam {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        store.launchSteam(in: bottle)
                    } label: {
                        Label("Open Steam", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    if games.isEmpty {
                        Text("No games installed yet. Open Steam and install one, and it will show up here.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)], spacing: 16) {
                            ForEach(games) { game in
                                GameCard(game: game) { store.launch(game, in: bottle) }
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Text("Steam isn’t installed in this bottle.").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await store.installSteam(in: bottle) }
                    } label: {
                        Label("Install Steam", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        section("Programs", systemImage: "square.grid.2x2") {
            if bottle.programs.isEmpty {
                Text("No pinned programs. Pin one from the list below, or open an .exe with “Run Program…”.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(bottle.programs) { program in
                        ProgramRow(program: program) {
                            Button("Unpin", systemImage: "pin.slash") { store.unpin(program, in: bottle) }
                                .labelStyle(.iconOnly)
                                .help("Remove from Programs")
                        } play: {
                            store.run(program, in: bottle)
                        }
                        if program.id != bottle.programs.last?.id { Divider() }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var discoveredSection: some View {
        let pinned = Set(bottle.programs.map(\.path))
        let candidates = discovered.filter { !pinned.contains($0.path) }
        if !candidates.isEmpty {
            section("Found Programs", systemImage: "magnifyingglass") {
                VStack(spacing: 0) {
                    ForEach(candidates) { program in
                        ProgramRow(program: program) {
                            Button("Pin", systemImage: "pin") { store.pin(program, in: bottle) }
                                .labelStyle(.iconOnly)
                                .help("Pin to Programs")
                        } play: {
                            store.run(program, in: bottle)
                        }
                        if program.id != candidates.last?.id { Divider() }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showImporter = true
            } label: {
                Label("Run Program…", systemImage: "plus.app")
            }
            .help("Run an .exe or .msi file")
            .disabled(!bottle.isInitialized)

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .help("Bottle settings")

            Menu {
                Section("Wine Tools") {
                    Button("Wine Configuration (winecfg)") { store.runTool("winecfg", in: bottle) }
                    Button("Registry Editor (regedit)") { store.runTool("regedit", in: bottle) }
                    Button("Task Manager (taskmgr)") { store.runTool("taskmgr", in: bottle) }
                    Button("File Explorer (explorer)") { store.runTool("explorer", in: bottle) }
                }
                .disabled(!bottle.isInitialized)
                Divider()
                Button("Open C: Drive in Finder", systemImage: "folder") { store.reveal(bottle.driveC) }
                Button("Show Logs", systemImage: "doc.text.magnifyingglass") { showLogs = true }
                Divider()
                Button("Stop All", systemImage: "stop.circle") { Task { await store.stop(bottle) } }
                Button("Delete Bottle…", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }
            .help("Tools")
        }
    }

    // MARK: - Helpers

    private func run(_ urls: [URL]) -> Bool {
        let files = urls.filter { ["exe", "msi"].contains($0.pathExtension.lowercased()) }
        guard bottle.isInitialized, !files.isEmpty else { return false }
        files.forEach { store.run($0, in: bottle) }
        return true
    }

    private func rescan() async {
        let snapshot = bottle
        let result = await Task.detached(priority: .utility) {
            (Steam.games(in: snapshot), ProgramScanner.scan(snapshot))
        }.value
        games = result.0
        discovered = result.1
    }

    private func section<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.title2.bold())
            content()
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func tag(_ text: String, _ symbol: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

private struct ProgramRow<Accessory: View>: View {
    let program: Program
    @ViewBuilder let accessory: Accessory
    let play: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name).font(.headline)
                Text(program.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            accessory.buttonStyle(.borderless)
            Button("Run", systemImage: "play.fill", action: play)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Run")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct GameCard: View {
    let game: SteamGame
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: game.headerURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "gamecontroller").font(.largeTitle).foregroundStyle(.secondary))
                    }
                }
                .aspectRatio(460.0 / 215.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if hovering {
                        RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.35))
                            .overlay(Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white))
                    }
                }
                Text(game.name).font(.headline).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play \(game.name)")
    }
}
