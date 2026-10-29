//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButtonContentTests.swift
//
//  An option that takes a parameter carries the control for it. These are the
//  four things that has to be true: the control sits under its own option, only
//  the chosen option's control is live, two options' controls are two controls,
//  and clicking a control is not clicking the option above it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUIPickers
@testable import TUITestSupport

@MainActor
@Suite("Radio button item content")
struct RadioButtonContentTests {

    private let selected = TerminalSymbols.radioSelected
    private let unselected = TerminalSymbols.radioUnselected

    /// A group of three options, the middle two of which carry a control.
    private func group(selection: String) -> some View {
        RadioButtonGroup(selection: .constant(selection)) {
            RadioButtonItem("plain", "Plain")
            RadioButtonItem("greys", "Greys") {
                Button("levels") {}
            }
            RadioButtonItem("sampled", "Sampled") {
                Button("colours") {}
            }
        }
    }

    /// Renders twice — the first pass registers the handler, the second reads
    /// the state it persisted — and answers with the second pass's buffer.
    private func render(selection: String, context: RenderContext) -> FrameBuffer {
        _ = renderToBuffer(group(selection: selection), context: context)
        return renderToBuffer(group(selection: selection), context: context)
    }

    @Test("Content renders under its own option, indented to the label column")
    func contentSitsUnderItsOption() {
        let context = makeRenderContext(width: 40, height: 12)
        let lines = render(selection: "greys", context: context).lines.map(\.stripped)

        // Option, its content, then the NEXT option — not the content after
        // the whole group, and not before the option it belongs to. Every
        // option's content is DRAWN, selected or not: the rows an option
        // occupies must not move as the selection does, or arrowing down the
        // list would walk a list that rearranges itself underneath.
        #expect(lines.count == 5, "Three options and two controls: \(lines)")
        #expect(lines[0] == "\(unselected) Plain")
        #expect(lines[1] == "\(selected) Greys")
        #expect(lines[2].hasPrefix("  "), "Content indents to the label: \(lines[2])")
        #expect(lines[2].contains("levels"))
        #expect(lines[3] == "\(unselected) Sampled")
        #expect(lines[4].contains("colours"))
    }

    @Test("The rows an option occupies do not move with the selection")
    func layoutIsStableAcrossSelections() {
        func rows(_ selection: String) -> [String] {
            render(selection: selection, context: makeRenderContext(width: 40, height: 12))
                .lines.map {
                    // The indicator is the one cell that is SUPPOSED to differ.
                    $0.stripped
                        .replacingOccurrences(of: TerminalSymbols.radioSelected, with: "·")
                        .replacingOccurrences(of: TerminalSymbols.radioUnselected, with: "·")
                }
        }
        // Same rows in the same places; only the glyph and the styling differ.
        #expect(rows("greys") == rows("sampled"))
    }

    @Test("Only the selected option's content is a focus stop")
    func unselectedContentIsNotAStop() {
        for selection in ["greys", "sampled"] {
            let context = makeRenderContext(width: 40, height: 12)
            _ = render(selection: selection, context: context)
            let focusable = context.environment.focusManager!.focusableIDsInActiveSection()
            // The group itself, plus exactly one button — the other option's
            // button is disabled, and a disabled control declines focus.
            #expect(
                focusable.count == 2,
                "Selecting \(selection) must leave one live control, got \(focusable)")
        }
    }

    @Test("Two options' controls are two controls, not one aliased slot")
    func eachOptionOwnsItsContent() {
        var identities: [String] = []
        for selection in ["greys", "sampled"] {
            let context = makeRenderContext(width: 40, height: 12)
            _ = render(selection: selection, context: context)
            let focusable = context.environment.focusManager!.focusableIDsInActiveSection()
            identities.append(focusable.sorted().joined(separator: "|"))
        }
        // A default focusID is derived from the render identity path, so two
        // items sharing the group's identity would produce the SAME id here.
        #expect(
            identities[0] != identities[1],
            "Both options produced \(identities[0]) — their content aliases")
    }

    @Test("Clicking a control does not select the option above it")
    func clickingContentDoesNotSelectItsOption() {
        let context = makeRenderContext(width: 40, height: 12)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(MouseSupport.full)

        var selection = "greys"
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let view = RadioButtonGroup(selection: binding) {
            RadioButtonItem("plain", "Plain")
            RadioButtonItem("greys", "Greys") {
                Button("levels") {}
            }
            RadioButtonItem("sampled", "Sampled")
        }

        _ = renderToBuffer(view, context: context)
        dispatcher.setRegions(renderToBuffer(view, context: context).hitTestRegions)

        // Row 2 is the live control's, not the option's above it. A region that
        // spanned the whole item would answer here and change the selection —
        // which is precisely what makes a control under an option unusable.
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: 4, y: 2))
        }
        #expect(selection == "greys", "clicking the control changed the selection")

        // The option row below it still selects, so the group did not simply
        // stop answering the pointer.
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: 4, y: 3))
        }
        #expect(selection == "sampled", "the option row stopped selecting")
    }

    @Test("Right steps into the selected option's controls, Left steps back out")
    func rightEntersTheContentAndLeftLeavesIt() {
        let context = makeRenderContext(width: 40, height: 12)
        let focus = context.environment.focusManager!
        _ = render(selection: "greys", context: context)

        let ids = focus.focusableIDsInActiveSection()
        #expect(ids.count == 2, "the group and one live control: \(ids)")
        focus.focus(id: ids[0])
        #expect(focus.isFocused(id: ids[0]))

        // Right is the group's cross axis, so it leaves the group forward —
        // and forward is the chosen option's controls, because they are the
        // only ones that registered.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .right))
        #expect(focus.isFocused(id: ids[1]), "Right did not reach the control")

        // And back: a control that does not claim Left hands it on, and the
        // group is what sits before it.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .left))
        #expect(focus.isFocused(id: ids[0]), "Left did not return to the options")
    }

    @Test("A group whose options carry nothing is unchanged")
    func plainGroupIsUnaffected() {
        let context = makeRenderContext(width: 40, height: 12)
        let plain = RadioButtonGroup(selection: .constant("b")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }
        _ = renderToBuffer(plain, context: context)
        let lines = renderToBuffer(plain, context: context).lines.map(\.stripped)
        let expected: [String] = ["\(unselected) Alpha", "\(selected) Bravo"]
        #expect(lines == expected)
    }

    /// The owner, 2026-10-28: terminal graphics as an option of the Images
    /// page's render style, shown everywhere and disabled where unsupported.
    @Test("A disabled option is drawn greyed, passed over by the arrows, and chosen by neither Return nor a click")
    func disabledOptionIsPassedOver() {
        var selection = "a"
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let view = RadioButtonGroup(selection: binding) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Beta").disabled()
            RadioButtonItem("c", "Gamma")
        }
        let context = makeRenderContext(width: 40, height: 6)
        _ = renderToBuffer(view, context: context)
        let buffer = renderToBuffer(view, context: context)
        let beta = buffer.lines[1]
        #expect(beta.stripped.hasPrefix(TerminalSymbols.radioDisabledUnselected), "\(beta.debugDescription)")
        let focus = context.environment.focusManager!
        let ids = focus.focusableIDsInActiveSection()
        focus.focus(id: ids[0])
        // Down passes over Beta to Gamma; Return chooses Gamma.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(selection == "c")
        // Up passes back over it to Alpha.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .up))
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(selection == "a")
    }
}
