//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MediumGuaranteedModifierTests.swift
//
//  `monospaced(_:)`, `monospacedDigit()`, `autocorrectionDisabled(_:)`,
//  `geometryGroup()`, `containerCornerOffset(_:sizeToFit:)`,
//  `flipsForRightToLeftLayoutDirection(_:)` and `scrollIndicatorsFlash` return `self`. Asserting THAT would prove nothing — every unimplemented
//  modifier passes such a test.
//
//  So these assert the guarantee instead: that equal character counts really
//  do occupy equal cell counts, and that a `TextField` binding really does
//  receive exactly what was typed. If the medium ever stopped holding up its
//  end, these fail and the modifiers stop being honest.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Modifiers the medium already satisfies")
struct MediumGuaranteedModifierTests {

    private func width(_ text: String) -> Int {
        measureChild(
            Text(verbatim: text), proposal: ProposedSize(width: 80, height: 1),
            context: makeRenderContext()
        ).width
    }

    // MARK: - The guarantee behind monospaced() / monospacedDigit()

    /// Every digit is one cell, so a number that changes cannot change width —
    /// which is the jitter `monospacedDigit()` exists to prevent.
    @Test("every digit occupies exactly one cell")
    func digitsAreUniform() {
        for digit in "0123456789" {
            #expect(width(String(digit)) == 1, "digit \(digit)")
        }
        // The case that actually bites in a proportional font: 1 vs 8.
        #expect(width("111111") == width("888888"))
        #expect(width("10%") == width("88%"))
    }

    /// …and the wider claim behind `monospaced(_:)`: it is not only digits.
    /// Narrow and wide ASCII advance the same, so a column of text lines up
    /// without anyone asking for a font.
    @Test("equal ASCII character counts occupy equal cell counts")
    func asciiIsUniform() {
        #expect(width("iiii") == 4)
        #expect(width("MMMM") == 4)
        #expect(width("il1|") == width("WM@%"))
    }

    /// The boundary worth stating: the guarantee is about the FONT, not about
    /// Unicode. An emoji is still two cells — `monospaced()` never promised
    /// otherwise, and pretending it did is the cells-not-characters bug.
    @Test("the guarantee is per-cell, not per-character")
    func wideCharactersStillTakeTwoCells() {
        #expect(width("🖥") == 2, "a wide glyph is still wide")
        #expect(width("ab") == 2)
    }

    // MARK: - The guarantee behind autocorrectionDisabled()

    /// A misspelling, an unusual capitalisation and a double space all arrive
    /// exactly as typed. Nothing between the key event and the binding rewrites
    /// them, which is why there is no autocorrection to disable.
    @Test("a text field receives exactly what was typed")
    func typedTextIsNeverRewritten() {
        let box = StateBox("")
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let focusManager = FocusManager()
        let context = makeRenderContext { environment, _ in
            environment.focusManager = focusManager
        }
        let view = TextField("Notes", text: binding).autocorrectionDisabled()

        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()

        // "teh" is the canonical autocorrect target; the lone "i" is the
        // canonical autocapitalisation target.
        for character in "teh  i" {
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character(character)))
        }
        #expect(box.value == "teh  i", "got \(box.value)")
    }
}

@MainActor
@Suite("Text's monospaced pair")
struct TextMonospacedTests {

    private func rendered(_ text: Text) -> String {
        renderToBuffer(text, context: makeRenderContext(width: 20, height: 1)).lines.first ?? ""
    }

    /// Identity, and that is why adding them alongside the `View` spellings is
    /// safe: which overload a call binds to cannot change what it does. The
    /// style toggles are NOT like this — see Parity-decisions-pending.md §9.
    /// The `View` overloads are a different symbol from `Text`'s, and a `Text`
    /// receiver always binds `Text`'s — so these are called on a stack, which is
    /// the only way the `View` copies are reached at all. The guarantee is that
    /// they change nothing.
    @Test("the View overloads are the same no-op on a non-Text view")
    func viewOverloadsAreNoOps() {
        let context = makeRenderContext(width: 20, height: 3)
        let bare = renderToBuffer(HStack { Text("Save 1234") }, context: context).lines
        #expect(renderToBuffer(HStack { Text("Save 1234") }.monospaced(), context: context).lines == bare)
        #expect(renderToBuffer(HStack { Text("Save 1234") }.monospacedDigit(), context: context).lines == bare)
        #expect(renderToBuffer(HStack { Text("Save 1234") }.autocorrectionDisabled(), context: context).lines == bare)
        #expect(renderToBuffer(HStack { Text("Save 1234") }.fontDesign(.monospaced), context: context).lines == bare)
        #expect(renderToBuffer(HStack { Text("Save 1234") }.fontDesign(nil), context: context).lines == bare)
    }

    @Test("both return the text unchanged")
    func monospacedIsIdentity() {
        let plain = rendered(Text(verbatim: "10%"))
        #expect(rendered(Text(verbatim: "10%").monospaced()) == plain)
        #expect(rendered(Text(verbatim: "10%").monospaced(false)) == plain)
        #expect(rendered(Text(verbatim: "10%").monospacedDigit()) == plain)
        #expect(rendered(Text(verbatim: "10%").fontDesign(.default)) == plain)
        #expect(rendered(Text(verbatim: "10%").fontDesign(.monospaced)) == plain)
    }

    // MARK: - The guarantees behind geometryGroup(), containerCornerOffset(_:sizeToFit:)
    // and flipsForRightToLeftLayoutDirection(_:)

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 12, height: 6)).lines.map(\.stripped)
    }

    /// An animation drives a modifier's value and the tree is laid out again
    /// from it, so every child of a moved parent moves by the parent's amount —
    /// the grouping `geometryGroup()` asks for.
    @Test("children move with their parent, as one")
    func childrenMoveWithTheirParent() {
        for step in 0...3 {
            let drawn = lines(VStack(alignment: .leading, spacing: 0) {
                Text("a")
                Text("bb")
            }.padding(.leading, step))
            #expect(drawn.prefix(2).map { $0.prefix(while: { $0 == " " }).count } == [step, step])
        }
        #expect(lines(Text("a").geometryGroup()) == lines(Text("a")))
    }

    /// A bordered container's corners sit in its border rows: the content row
    /// right below the top edge is bounded by the side walls alone.
    @Test("a container's corners take no content cells")
    func cornersTakeNoContent() {
        let drawn = lines(Text("x").border())
        #expect(drawn.map { $0.first } == ["╭", "│", "╰"])
        #expect(drawn[1].contains("x"))
        #expect(lines(Text("x").containerCornerOffset(.all, sizeToFit: true).border()) == drawn)
    }

    /// Nothing can set a right-to-left layout, which is the only one that flips.
    @Test("the layout direction is left-to-right")
    func layoutIsLeftToRight() {
        #expect(makeRenderContext().environment.layoutDirection == .leftToRight)
        #expect(lines(Text("ab").flipsForRightToLeftLayoutDirection(true)) == lines(Text("ab")))
    }

    // MARK: - scenePadding

    @Test("scene padding is the padding() default, on the edges asked for")
    func scenePadding() {
        #expect(lines(Text("a").scenePadding()) == lines(Text("a").padding()))
        #expect(lines(Text("a").scenePadding(.leading)) == lines(Text("a").padding(.leading)))
        #expect(lines(Text("a").scenePadding(.minimum, edges: .top)) == lines(Text("a").padding(.top, 1)))
    }

    // MARK: - scrollIndicatorsFlash

    /// What a flash is for — seeing that the content goes on — holds from the
    /// first frame: an overflowing scroll view draws its indicator before
    /// anything has scrolled, in either style.
    @Test("an overflowing scroll view shows its indicators on its first frame")
    func indicatorsShowWithoutAFlash() {
        func firstFrame(_ style: ScrollIndicatorStyle) -> [String] {
            var environment = EnvironmentValues()
            environment.scrollIndicatorStyle = style
            let context = RenderContext(
                availableWidth: 12, availableHeight: 5, environment: environment, tuiContext: TUIContext()
            ).isolatingRenderCache()
            let view = ScrollView {
                VStack(spacing: 0) { ForEach(0..<20, id: \.self) { Text("row \($0)") } }
            }
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: 1)
            return renderToBuffer(view, context: context).lines.map(\.stripped)
        }
        let bar = firstFrame(.scrollbar)
        #expect(bar.contains { $0.contains("▲") } && bar.contains { $0.contains("▼") }, "\(bar)")
        let text = firstFrame(.text)
        #expect(text.contains { $0.contains("▼") }, "\(text)")
    }
}
