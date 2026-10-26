//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlGroupTests.swift
//
//  SwiftUI's ControlGroup and its styles.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIMenus
@testable import TUITestSupport

/// Puts the label in front of the current group.
private struct Prefixed: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.label
            ControlGroup(configuration)
        }
    }
}

@MainActor
@Suite("ControlGroup")
struct ControlGroupTests {

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 3))
            .lines.first?.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) ?? ""
    }

    private var group: some View {
        ControlGroup {
            Button("Bold") {}
            Button("Italic") {}
        } label: {
            Text("Format")
        }
    }

    @Test("The default style draws the controls as one segmented face, as a segmented picker is drawn")
    func automatic() {
        let drawn = line(group)
        #expect(drawn == "▐ Bold │ Italic ▌", "caps at the ends, a rule between: \(drawn)")
        #expect(!drawn.contains("Format"), "the label is for a menu or an overflow, not drawn beside")
    }

    /// As `PickerSegmentsTests.capsFollowTheFamily` pins a segmented picker's.
    @Test("The face's caps and rules are a segmented picker's in the control family and shape (CONTROLGROUP-LOOK)")
    func capsFollowTheFamily() {
        #expect(line(group.controlStyle(.lines)) == "( Bold │ Italic )")
        #expect(line(group.controlStyle(.lines).buttonBorderShape(.roundedRectangle)) == "│ Bold │ Italic │")
        #expect(line(group.controlStyle(.blank)) == " Bold │ Italic", "no caps under blank")
        #expect(line(group.controlSize(.mini)) == "Bold│Italic", "no caps at mini, as a picker's")
    }

    @Test("At the large sizes the group stays one row, as a segmented picker does")
    func oneRowWhenLarge() {
        let drawn = renderToBuffer(group.controlSize(.large), context: makeRenderContext(width: 40, height: 5))
        #expect(drawn.height == 1, "\(drawn.lines.map(\.stripped))")
        #expect(drawn.lines.first?.stripped.hasPrefix("▐ Bold │ Italic ▌") == true)
    }

    @Test("A button outside a group keeps its caps, and a presented surface leaves the group's segments behind")
    func segmentsStayInTheGroup() {
        #expect(line(HStack(spacing: 0) { group; Button("Next") {} }) == "▐ Bold │ Italic ▌▐ Next ▌")
        var context = makeRenderContext(width: 40, height: 3)
        context.environment.isControlSegment = true
        context.leavePresenter()
        #expect(!context.environment.isControlSegment)
    }

    @Test("The menu style puts the controls behind the label")
    func menuStyle() {
        let drawn = line(group.controlGroupStyle(.menu))
        #expect(drawn.contains("Format") && !drawn.contains("Italic"))
    }

    @Test("ControlGroup(configuration) keeps the label and draws as the style outside")
    func configuration() {
        let drawn = line(group.controlGroupStyle(Prefixed()))
        #expect(drawn.hasPrefix("Format ") && drawn.contains("Bold") && drawn.contains("Italic"))
        let overMenu = line(group.controlGroupStyle(Prefixed()).controlGroupStyle(.menu))
        #expect(overMenu.hasPrefix("Format ") && !overMenu.contains("Italic"),
                "inside, the menu style that was in force outside: \(overMenu)")
    }
}
