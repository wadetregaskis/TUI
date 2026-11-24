//  🖥️ TUI — A Terminal UI framework for Swift
//  FadedControlClicksTests.swift
//
//  A control under an `.opacity(_:)` below 1/48 takes no click, as SwiftUI's
//  does (bug hunt H-68b; measured, `Tools/SwiftUIProbes/A control at opacity
//  zero (H-68b)/faded.out`): a button at `.opacity(0)`, at `0.0208` or under
//  an ancestor's `.opacity(0)` is not clicked, one at `0.0209` or more is, and
//  each modifier's own value decides, not their product. Tab still stops on
//  it, as SwiftUI's does. Until 2026-11-23 a faded control kept its clicks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the faded button heard.
@MainActor
private final class ClickLog {
    var saves = 0
}

@MainActor
@Suite("A faded control's clicks", .serialized)
struct FadedControlClicksTests {
    /// A button at the top leading corner of a 20 × 3 frame, faded by `fade`.
    private func page(_ log: ClickLog, _ fade: @escaping (AnyView) -> AnyView) -> some View {
        fade(AnyView(Button("Save") { log.saves += 1 })).frame(width: 20, height: 3)
    }

    /// Whether a click in the middle of the button `fade` fades, at (4, 0),
    /// reaches it.
    private func clickReaches(_ fade: @escaping (AnyView) -> AnyView) -> Bool {
        let log = ClickLog()
        let harness = InputChainHarness()
        harness.frame(page(log, fade))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 4, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 4, y: 0))
        harness.frame(page(log, fade))
        return log.saves == 1
    }

    @Test("At opacity 1 the click reaches the button (the probe's control)")
    func opaque() {
        #expect(clickReaches { $0 })
    }

    @Test("A button at .opacity(0) takes no click")
    func zero() {
        #expect(!clickReaches { AnyView($0.opacity(0)) })
    }

    @Test("A button at .opacity(0.0208) takes no click, and one at .opacity(0.0209) takes it")
    func cut() {
        #expect(!clickReaches { AnyView($0.opacity(0.0208)) })
        #expect(clickReaches { AnyView($0.opacity(0.0209)) })
    }

    @Test("A button at .opacity(0.5) takes the click")
    func half() {
        #expect(clickReaches { AnyView($0.opacity(0.5)) })
    }

    @Test("An ancestor's .opacity(0) takes the click away")
    func ancestor() {
        #expect(!clickReaches { button in AnyView(VStack { button }.opacity(0)) })
    }

    @Test("Each modifier's own value decides: .opacity(0).opacity(1) takes none, two .opacity(0.1) take it")
    func perModifier() {
        #expect(!clickReaches { AnyView($0.opacity(0).opacity(1)) })
        #expect(clickReaches { AnyView($0.opacity(0.1).opacity(0.1)) })
    }

    @Test("Tab still stops on a faded control, as SwiftUI's does")
    func focusKept() {
        let harness = InputChainHarness()
        let page = VStack {
            Button("First") {}
            Button("Faded") {}.opacity(0)
        }
        harness.frame(page)
        let ring = harness.focusManager.sections.flatMap(\.focusables).filter(\.canBeFocused)
        #expect(ring.count == 2, "both buttons are in the focus ring")
    }
}
