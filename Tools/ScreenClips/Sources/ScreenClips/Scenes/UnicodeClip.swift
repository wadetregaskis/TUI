//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnicodeClip.swift
//
//  `unicode`: one phrasebook, filmed in Ghostty, iTerm2, Terminal.app and
//  Warp and shown as a carousel of the four — emoji with skin tones, ZWJ
//  sequences and flags, CJK, combining marks and right-to-left scripts, laid
//  out in columns that stay columns in every one of them.
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
    // left of it, so this one shot frames the same cells in each: the
    // phrasebook alone, at a size the carousel's cards keep legible.
    var script: [Step] = [.camera(Shot(x: 0, y: 3, width: 48, height: 12)), .wait(0.8)]
    for _ in 0..<7 { script += [.down, .wait(0.1), .space, .wait(0.65)] }
    for _ in 0..<7 { script += [.up, .wait(0.05), .space, .wait(0.25)] }
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

/// A phrasebook: a table of greetings, and under it a line of what else a
/// terminal has to get right — emoji sequences and combining marks.
///
/// No Devanagari: Apple Terminal draws it at the font's proportional advance
/// and moves the rest of its row left, which no emission repairs (Terminal
/// compatibility survey, "What Apple Terminal paints"), and this clip is
/// filmed there too.
struct Phrasebook: View {
    @State private var selection: Int? = 0

    private let greetings: [Greeting] = [
        Greeting(id: 0, flag: "🇯🇵", language: "日本語", hello: "こんにちは、世界"),
        Greeting(id: 1, flag: "🇨🇳", language: "中文", hello: "你好，世界"),
        Greeting(id: 2, flag: "🇰🇷", language: "한국어", hello: "안녕하세요, 세계"),
        Greeting(id: 3, flag: "🇸🇦", language: "العربية", hello: "مرحبا بالعالم"),
        Greeting(id: 4, flag: "🇮🇱", language: "עברית", hello: "שלום עולם"),
        Greeting(id: 5, flag: "🇻🇳", language: "Tiếng Việt", hello: "Xin chào thế giới"),
        Greeting(id: 6, flag: "🇬🇷", language: "Ελληνικά", hello: "Γειά σου κόσμε"),
        // "Zoë" and "Åsa" spelled with COMBINING marks (e + U+0308, A + U+030A),
        // not the precomposed letters: one cell each, however they are spelled.
        Greeting(id: 7, flag: "🇸🇪", language: "Svenska", hello: "Hej Zoe\u{0308} och A\u{030A}sa"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(greetings, selection: $selection) {
                TableColumn("", value: \Greeting.flag).width(2)
                TableColumn("Language", value: \Greeting.language).width(11)
                TableColumn("Hello", value: \Greeting.hello)
            }
            .frame(width: 46, height: 11)
            HStack(spacing: 1) {
                Text(verbatim: "👩‍💻 🧑🏽‍🚀 ❤️‍🔥 🏳️‍🌈 🫶🏾")
                Text(verbatim: "Ǻ ṩ ḉ").foregroundStyle(.palette.foregroundSecondary)
                Spacer(minLength: 0)
                Spinner()
                Text(verbatim: "同期中… \(selection.map { greetings[$0].flag } ?? "") ")
                    .foregroundStyle(.palette.foregroundSecondary)
            }
            .frame(width: 46)
            .padding(.leading, 1)
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Phrasebook · 8 languages") }
        }
    }
}
