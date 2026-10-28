//  🖥️ TUI — A Terminal UI framework for Swift
//  UnicodeClip.swift
//
//  `unicode`: one phrasebook, filmed in Ghostty, iTerm2, Terminal.app and
//  Warp and shown as a carousel of the four — emoji with skin tones, ZWJ
//  sequences and flags, CJK, Hangul, Cyrillic, Georgian, Greek and combining
//  marks, laid out in columns that stay columns in every one of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

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

/// The cards hold still — the carousel's slide and each card's spinner are
/// the motion — so the four films cost far less than a moving selection in
/// each did (739 KB, over budget).
private func unicodeScript() -> [Step] {
    // Every terminal's window is at least 80×24 (iTerm2's is its profile's,
    // 80×25; Warp's is whatever its window is), and the app draws in the top
    // left of it, so this one shot frames the same cells in each: the
    // phrasebook alone, at a size the carousel's cards keep legible.
    [.camera(Shot(x: 0, y: 3, width: 48, height: 14)), .wait(8.0)]
}

struct UnicodeApp: App {
    var body: some Scene {
        WindowGroup("TUI · Unicode") {
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
/// filmed there too. And no Arabic or Hebrew: TUI does not reorder a
/// right-to-left run, nor do the terminals filmed, so it would read backwards
/// (the survey's "Right-to-left text").
struct Phrasebook: View {
    @State private var selection: Int? = 0

    private let greetings: [Greeting] = [
        Greeting(id: 0, flag: "🇯🇵", language: "日本語", hello: "こんにちは、世界"),
        Greeting(id: 1, flag: "🇨🇳", language: "中文", hello: "你好，世界"),
        Greeting(id: 2, flag: "🇰🇷", language: "한국어", hello: "안녕하세요, 세계"),
        Greeting(id: 3, flag: "🇺🇦", language: "Українська", hello: "Привіт, світе"),
        Greeting(id: 4, flag: "🇬🇪", language: "ქართული", hello: "გამარჯობა, სამყარო"),
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
            // Centred under the table (the owner's review, 2026-10-27, which
            // also took out a spinner and a CJK status here: the table already
            // has non-Latin text and flags).
            HStack(spacing: 1) {
                // Few ZWJ sequences: Apple Terminal and Warp draw each as its
                // components, wider, and a longer line wrapped there.
                Text(verbatim: "👩‍💻 ❤️‍🔥 🫶🏾 🎉")
                Text(verbatim: "Ǻ ṩ ḉ").foregroundStyle(.palette.foregroundSecondary)
            }
            // `.center` said: a fixed frame's default is top-leading here
            // (compatibility guide §2.7).
            .frame(width: 46, alignment: .center)
            // A row of space under the strip, for the camera's bottom edge:
            // a carousel's cards take one shape, which may shave a row.
            Color.clear.frame(height: 1)
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Phrasebook · 8 languages") }
        }
    }
}
