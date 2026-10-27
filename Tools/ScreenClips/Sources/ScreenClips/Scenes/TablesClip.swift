//  🖥️ TUI — A Terminal UI framework for Swift
//  TablesClip.swift
//
//  `tables`: an activity monitor's process table, its numbers live — scrolled
//  under a header that stays put, sorted by a click on a column's header and
//  then on another, a row selected and followed, and then filtered by name
//  through `.searchable`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let tablesClip = Clip(
    id: "tables",
    title: "Tables",
    columns: 112,
    rows: 32,
    output: 800,
    script: tablesScript(),
    run: { await TablesApp.main() }
)

/// Header cells, as the table lays them out (row 8 of the window: the toolbar
/// takes three rows; the summary line, a gap, the search field and the
/// table's top border five more).
private enum TableHeader {
    static let row = 8
    static let cpu = 38
    static let name = 14
}

private func tablesScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0.6, y: 3, width: 73, height: 21)), .wait(1.0)]
    // Down through the rows, past the bottom: the header stays.
    script += Step.repeat(.down, 6, interval: 0.18)
    script += [.wait(0.3), .pageDown, .wait(0.9), .pageDown, .wait(0.9)]
    // Sorted by CPU, busiest first (a second click reverses it).
    script += Step.click(TableHeader.cpu, TableHeader.row)
    script += [.wait(1.1)]
    script += Step.click(TableHeader.cpu, TableHeader.row)
    script += [.wait(1.6), .home, .wait(0.5)]
    script += Step.repeat(.down, 3, interval: 0.3)
    script += [.wait(1.2)]
    // Then by name, and back to the top.
    script += Step.click(TableHeader.name, TableHeader.row)
    script += [.wait(1.4), .home, .wait(0.8)]
    // Into the search field (Shift-Tab: it comes before the table), a name
    // typed, and cleared again (Ctrl-U) where it began.
    script += [.keys("\u{1B}[Z"), .wait(0.5)]
    script += Step.type("swift", interval: 0.22)
    script += [.wait(1.8), .control("u"), .wait(0.6), .keys("\t"), .wait(0.8)]
    return script
}

struct TablesApp: App {
    var body: some Scene {
        WindowGroup("TUI · Tables") {
            ActivityMonitor()
                .palette(AppleTerminalPalette(.ocean))
        }
    }
}

/// One process, as the table shows it.
struct ProcessRow: Identifiable, Hashable {
    let id: Int
    let name: String
    let user: String
    var cpu: Double
    var memory: Double
    var threads: Int

    var cpuText: String { String(format: "%5.1f", cpu) }
    var memoryText: String { memory >= 1024 ? String(format: "%.2f GB", memory / 1024) : String(format: "%.0f MB", memory) }
}

/// The processes, their numbers moving on a clock of their own.
struct ActivityMonitor: View {
    @State private var tick = 0
    @State private var selection: Int?
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.id)]
    @State private var query = ""

    private static let names: [(String, String)] = [
        ("kernel_task", "root"), ("WindowServer", "_windowserver"), ("Ghostty", "ada"), ("swift-frontend", "ada"),
        ("Xcode", "ada"), ("Safari", "ada"), ("mds_stores", "root"), ("Music", "ada"), ("launchd", "root"),
        ("sourcekit-lsp", "ada"), ("Mail", "ada"), ("coreaudiod", "_coreaudiod"), ("photoanalysisd", "ada"),
        ("Finder", "ada"), ("cloudd", "ada"), ("bluetoothd", "root"), ("Dock", "ada"), ("Calendar", "ada"),
        ("Notes", "ada"), ("syslogd", "root"), ("trustd", "root"), ("Terminal", "ada"), ("ssh-agent", "ada"),
        ("git", "ada"), ("zsh", "ada"), ("Preview", "ada"), ("Messages", "ada"), ("softwareupdated", "root"),
        ("distnoted", "ada"), ("powerd", "root"), ("Spotlight", "ada"), ("Maps", "ada"), ("Photos", "ada"),
        ("nsurlsessiond", "ada"), ("hidd", "_hidd"), ("lldb-rpc-server", "ada"), ("clangd", "ada"),
        ("TextEdit", "ada"), ("Activity Monitor", "ada"), ("swift-build", "ada"),
    ]

    private var rows: [ProcessRow] {
        let rows = Self.names.enumerated().map { index, entry in
            // The busiest few wobble, out of step with each other; the rest
            // idle at a steady figure (a whole table of changing numbers is a
            // whole table of changed pixels, every frame of the clip).
            let phase = Double(tick + index * 7)
            let base = Double((index * 37) % 23) + (index < 5 ? 30 : 0)
            let cpu = index < 6 ? max(0, base + 6 * sin(phase / 3) + Double((tick * (index + 3)) % 5)) : base / 4
            return ProcessRow(
                id: 100 + index * 41, name: entry.0, user: entry.1, cpu: cpu,
                memory: Double((index * 97) % 900 + 40) * (index < 6 ? 4.2 : 1),
                threads: (index * 13) % 40 + 2)
        }
        return rows
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(verbatim: "\(rows.count) processes").bold()
                Text(verbatim: "CPU 31.4%").foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: "Memory 18.4 of 32 GB").foregroundStyle(.palette.foregroundSecondary)
                Spacer()
                ProgressView(value: min(1, rows.map(\.cpu).reduce(0, +) / 800))
                    .frame(width: 20)
            }
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("PID", value: \ProcessRow.id) { Text(verbatim: "\($0.id)") }
                    .width(6).alignment(.trailing)
                TableColumn("Process", value: \ProcessRow.name).width(20)
                TableColumn("% CPU", value: \ProcessRow.cpu) { Text(verbatim: $0.cpuText) }
                    .width(7).alignment(.trailing)
                TableColumn("Memory", value: \ProcessRow.memory) { Text(verbatim: $0.memoryText) }
                    .width(9).alignment(.trailing)
                TableColumn("Threads", value: \ProcessRow.threads) { Text(verbatim: "\($0.threads)") }
                    .width(8).alignment(.trailing)
                TableColumn("User", value: \ProcessRow.user)
            }
            .searchable(text: $query, prompt: "Filter processes")
            // Held at the top when a filter leaves only a few rows: without it
            // the page centred itself in the window as the table shrank.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Activity") }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1000))
                tick += 1
            }
        }
    }
}
