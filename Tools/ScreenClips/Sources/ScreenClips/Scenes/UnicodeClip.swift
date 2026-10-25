//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnicodeClip.swift
//
//  `unicode`: one phrasebook, filmed in Ghostty, iTerm2, Terminal.app and
//  Warp and shown as a carousel of the four — emoji with skin tones, ZWJ
//  sequences and flags, CJK, combining marks, right-to-left scripts and box
//  drawing, laid out in columns that stay columns in every one of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let unicodeClip = Clip(
    id: "unicode",
    title: "Unicode",
    columns: 80,
    rows: 24,
    carousel: ["ghostty", "iterm", "apple", "warp"],
    output: 800,
    script: unicodeScript(),
    run: { await UnicodeApp.main() }
)

/// The selection walks down the phrasebook and back up: something is always
/// moving, whichever card is in front when.
private func unicodeScript() -> [Step] {
    // Every terminal's window is at least 80×24 (iTerm2's is its profile's,
    // 80×25; Warp's is whatever its window is), and the app draws in the top
    // left 80×24 of it, so this one shot frames the same cells in each.
    var script: [Step] = [.camera(Shot(x: 0.4, y: 3.5, width: 79.2, height: 19.8)), .wait(0.8)]
    for _ in 0..<8 { script += [.down, .wait(0.1), .space, .wait(0.65)] }
    for _ in 0..<8 { script += [.up, .wait(0.05), .space, .wait(0.25)] }
    script += [.wait(0.3)]
    return script
}

struct UnicodeApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Unicode") {
            Phrasebook()
                .frame(width: 80, height: 24, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .palette(LiveTerminalPalette())
        }
    }
}

/// One way to say hello.
struct Greeting: Identifiable {
    let id: Int
    let flag: String
    let language: String
    let hello: String
}

/// A phrasebook: a table of greetings, and beside it what else a terminal has
/// to get right — emoji sequences, flags, combining marks, box drawing.
struct Phrasebook: View {
    @State private var selection: Int? = 0

    private let greetings: [Greeting] = [
        Greeting(id: 0, flag: "🇯🇵", language: "日本語", hello: "こんにちは、世界"),
        Greeting(id: 1, flag: "🇨🇳", language: "中文", hello: "你好，世界"),
        Greeting(id: 2, flag: "🇰🇷", language: "한국어", hello: "안녕하세요, 세계"),
        Greeting(id: 3, flag: "🇸🇦", language: "العربية", hello: "مرحبا بالعالم"),
        Greeting(id: 4, flag: "🇮🇱", language: "עברית", hello: "שלום עולם"),
        Greeting(id: 5, flag: "🇮🇳", language: "हिन्दी", hello: "नमस्ते दुनिया"),
        Greeting(id: 6, flag: "🇻🇳", language: "Tiếng Việt", hello: "Xin chào thế giới"),
        Greeting(id: 7, flag: "🇬🇷", language: "Ελληνικά", hello: "Γειά σου κόσμε"),
        // "Zoë" and "Åsa" spelled with COMBINING marks (e + U+0308, A + U+030A),
        // not the precomposed letters: one cell each, however they are spelled.
        Greeting(id: 8, flag: "🇸🇪", language: "Svenska", hello: "Hej Zoe\u{0308} och A\u{030A}sa"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Table(greetings, selection: $selection) {
                TableColumn("", value: \Greeting.flag).width(2)
                TableColumn("Language", value: \Greeting.language).width(11)
                TableColumn("Hello", value: \Greeting.hello)
            }
            .frame(width: 45)

            VStack(alignment: .leading, spacing: 0) {
                GroupBox("Emoji") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "👩‍💻 🧑🏽‍🚀 👨‍👩‍👧‍👦 🫶🏾 ❤️‍🔥")
                        Text(verbatim: "🏳️‍🌈 🇬🇧 🇫🇷 🇧🇷 🇿🇦 🇨🇦 🇳🇿")
                    }
                }
                GroupBox("Marks") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Ǻ ṩ ḉ ẍ̃ — q\u{0323}\u{0307} n\u{0303}\u{0301}")
                        Text(verbatim: "Đặc biệt · o\u{0308}\u{0332} · Z\u{0351}\u{0363}a\u{0334}l\u{0353}g\u{0308}o")
                    }
                }
                GroupBox("Boxes") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "┌─┬─┐ ╔═╦═╗ ╭───╮ ▁▂▃▅▇")
                        Text(verbatim: "└─┴─┘ ╚═╩═╝ ╰───╯ ░▒▓█▌")
                    }
                }
                HStack(spacing: 1) {
                    Spinner()
                    Text(verbatim: "同期中… \(selection.map { greetings[$0].flag } ?? "") ")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                .padding(.leading, 1)
            }
            .frame(width: 33)
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Phrasebook · 9 languages") }
        }
    }
}
