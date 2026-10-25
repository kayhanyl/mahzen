import SwiftUI

struct LogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var files: [URL] = []
    @State private var selected: URL?
    @State private var text = ""

    /// Logs of a chatty game can grow large; only the tail is worth reading.
    private static let tailBytes: UInt64 = 512 * 1024

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(files, id: \.self, selection: $selected) { url in
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

                Group {
                    if selected == nil {
                        ContentUnavailableView("No Logs", systemImage: "doc.text",
                                               description: Text("Logs appear here when you run a program in this bottle."))
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            Text(text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(10)
                        }
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Button("Reload", systemImage: "arrow.clockwise") { reload() }
                    .keyboardShortcut("r")
                Button("Show in Finder", systemImage: "folder") { store.reveal(bottle.logs) }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 900, height: 560)
        .onAppear(perform: reload)
        .onChange(of: selected) { load() }
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: bottle.logs, includingPropertiesForKeys: nil)) ?? []
        // File names start with yyyyMMdd-HHmmss, so name order is time order.
        files = urls.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        if selected == nil || !files.contains(selected!) { selected = files.first }
        load()
    }

    private func load() {
        guard let selected, let handle = try? FileHandle(forReadingFrom: selected) else {
            text = ""
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > Self.tailBytes ? size - Self.tailBytes : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        let body = String(decoding: data, as: UTF8.self)
        text = start > 0 ? String(localized: "… (showing only the last 512 KB)") + "\n\n" + body : body
    }
}
