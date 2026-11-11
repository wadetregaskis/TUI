//  🖥️ TUI — A Terminal UI framework for Swift
//  TransliteratedGlyphTests.swift
//
//  Where text is spelled in ASCII (`TUI_PLAIN_TEXT`), the framework's own
//  glyphs take their ASCII forms where they are drawn: a toggle's `[x]`, a
//  radio button's `(*)`, a spinner's frames. Folded at output instead, `■` and
//  `□` were both `#`, `⬛︎` and `◯` blank, and half the spinners stood still or
//  showed nothing (the owner's evening feedback, 2026-11-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Framework glyphs where text is spelled in ASCII")
struct TransliteratedGlyphTests {
    private func drawn(_ view: some View, width: Int = 40, height: Int = 8) -> [String] {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.textSpelling = .ascii(.standard)
        }
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("A toggle draws [x] and [ ], whatever its character set, and as written does not")
    func toggleMarks() {
        for set in [ToggleCharacterSet.unicode, .emoji, .automatic] {
            let on = drawn(Toggle("On", isOn: .constant(true)).toggleCharacterSet(set)).joined()
            let off = drawn(Toggle("Off", isOn: .constant(false)).toggleCharacterSet(set)).joined()
            #expect(on.contains("[x] On"), "\(on)")
            #expect(off.contains("[ ] Off"), "\(off)")
        }
        var environment = EnvironmentValues()
        environment.toggleCharacterSet = .emoji
        #expect(environment.effectiveToggleCharacterSet == .emoji)
        environment.textSpelling = .ascii(.standard)
        #expect(environment.effectiveToggleCharacterSet == .ascii)
        // A set that is ASCII already is the app's, and kept.
        let custom = ToggleCharacterSet(onMark: "*", offMark: "-", openBracket: "<", closeBracket: ">")
        environment.toggleCharacterSet = custom
        #expect(environment.effectiveToggleCharacterSet == custom)
    }

    /// The search field's magnifier, drawn only with emoji chrome, was
    /// spelled `:right_pointing_magnifying_glass:` beside the field.
    @Test("Spelling words or keys in ASCII turns emoji chrome off")
    func emojiChromeOff() {
        var environment = EnvironmentValues()
        environment.supportsEmojiChrome = true
        environment.spellTextInASCII()
        #expect(!environment.supportsEmojiChrome)
        environment.supportsEmojiChrome = true
        environment.spellKeysInASCII()
        #expect(!environment.supportsEmojiChrome)
    }

    @Test("A radio group marks every option, the selected one with a star")
    func radioMarks() {
        let rows = drawn(
            RadioButtonGroup(selection: .constant("b")) {
                RadioButtonItem("a", "Alpha")
                RadioButtonItem("b", "Bravo")
            })
        #expect(rows.contains { $0.hasPrefix("( ) Alpha") }, "\(rows)")
        // Selected, or focused, which a lone group is: either way the star.
        #expect(rows.contains { $0.hasPrefix("(*) Bravo") }, "\(rows)")
    }

    @Test(
        "Every built-in spinner has ASCII frames, one cell each, that move",
        arguments: [
            SpinnerStyle.dots, .line, .dancingLine, .pie, .beachball, .box, .curve, .column, .bar, .shade,
            .blockWedge, .spinningTriangle, .moon, .earth, .clock,
        ])
    func spinnerFrames(style: SpinnerStyle) {
        let frames = style.asciiFrames
        #expect(frames.allSatisfy { $0.utf8.count == 1 && $0.utf8.allSatisfy { $0 < 0x80 } }, "\(frames)")
        #expect(Set(frames).count > 1, "\(frames)")
    }

    /// A track as the terminal is sent it: folded at output, `.bar`'s `▌` was a
    /// control's closing end, `]`, so the bar read `]]]]]]]]--------`; `.dot`'s
    /// `▬` has no shape and was blank; a Braille track's empty cells were dots
    /// as its fill was; and `.knob`'s rail was `-` on both sides of the knob.
    @Test(
        "A track's fill reads as one in ASCII, and apart from the rest of the track",
        arguments: [TrackStyle.bar, .blockFine, .dot, .braille, .knob, .shade, .block])
    func trackGlyphs(style: TrackStyle) {
        // 0.525 of 20 cells ends half way through the eleventh: `.blockFine`'s `▌`.
        let drawnLine = drawn(ProgressView(value: 0.525).trackStyle(style), width: 20, height: 1).joined()
        let line = PlainTerminalText.folding(drawnLine)
        #expect(!line.contains("]") && !line.contains("["), "\(line)")
        #expect(line.first != " ", "the fill is blank: \(line)")
        #expect(line.first != line.last, "the fill reads as the rest of the track: \(line)")
    }

    /// A control's half-block ends, `▐ … ▌`, are its brackets where it draws
    /// them, since the folding writes a half block as the `#` it is: a
    /// button's, a field's, and through `ControlEnds` a segmented picker's, a
    /// tab chip's and a control group's. As written they are half blocks.
    @Test("A control's half-block ends are brackets, and only where text is spelled in ASCII")
    func controlEnds() {
        let button = drawn(Button("OK") {}).joined()
        #expect(button.contains("[ OK ]"), "\(button)")
        let field = drawn(TextField("Name", text: .constant("Ada")).frame(width: 10)).joined()
        #expect(field.hasPrefix("[Ada") && field.contains("]"), "\(field)")
        let segments = PlainTerminalText.folding(
            drawn(
                Picker("", selection: .constant(1)) {
                    Text("S").tag(1)
                    Text("M").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            ).joined())
        #expect(segments.contains("[ S | M ]"), "\(segments)")

        var environment = EnvironmentValues()
        let asWritten = ControlEnds(in: environment)
        #expect((asWritten.open, asWritten.close) == ("▐", "▌"))
        environment.textSpelling = .ascii(.standard)
        let ascii = ControlEnds(in: environment)
        #expect((ascii.open, ascii.close) == ("[", "]"))
        let written = renderToBuffer(Button("OK") {}, context: makeRenderContext(width: 40, height: 8))
        #expect(written.lines.map(\.stripped).joined().contains("▐ OK ▌"))
    }

    /// Folded at output, the dial's quarters `◔ ◑ ◕` have no shape and were
    /// blank, and `○` and `●` are both `o`: empty and full read alike.
    @Test("A tiny circular gauge draws a different ASCII mark at each quarter, none blank")
    func tinyDial() {
        let marks = [0.0, 0.25, 0.5, 0.75, 1.0].map { value in
            let dial = drawn(Gauge(value: value) { EmptyView() }.gaugeStyle(.accessoryCircularTiny), width: 4, height: 1)
            return PlainTerminalText.folding(dial.joined()).trimmingCharacters(in: .whitespaces)
        }
        #expect(Set(marks).count == 5 && !marks.contains(""), "\(marks)")
    }

    @Test("A spinner draws its ASCII frame, and a bouncing one its track in dots")
    func spinnerDrawn() {
        let moon = drawn(Spinner(style: .moon)).joined()
        #expect(SpinnerStyle.moon.asciiFrames.contains(moon.trimmingCharacters(in: .whitespaces)), "\(moon)")
        let bouncing = drawn(Spinner(style: .bouncing)).joined()
        #expect(bouncing.contains("."), "\(bouncing)")
        #expect(!bouncing.contains("●"), "\(bouncing)")
        let custom = drawn(Spinner(style: .custom("🙂"))).joined()
        #expect(custom.contains(":)"), "\(custom)")
    }
}
