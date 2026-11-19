//  🖥️ TUI — A Terminal UI framework for Swift
//  HoverOwedFrameTests.swift
//
//  A frame whose hit regions change what it shows under the resting pointer
//  after it is drawn — the hover's reconcile entering a view a reshape slid
//  under the pointer, a menu's highlight moved to the row under it — owes the
//  frame that draws the change, and that frame is drawn before the next input
//  is handled. Handled first, a key acted on a state the screen had not drawn:
//  Return ran a menu row the screen had not lit (the Stress menus session, at
//  its step 803). The run loop holds its reading for it
//  (`AppRunner.frameDrawn(renderer:hold:)`), `HeadlessApp` draws it as the next
//  event arrives.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// A row with an `.onHover` that shows whether it is hovered, which a key
/// moves down a row, under a pointer resting there.
private struct LitRowApp: App {
    var body: some Scene {
        WindowGroup {
            LitRowPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct LitRowPage: View {
    @State private var pushed = false
    @State private var lit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pushed { Text("spacer") }
            Text(lit ? "row LIT" : "row dark").onHover { lit = $0 }
        }
        .onKeyEvent(keys: [.character("n")]) { _ in
            pushed.toggle()
            return true
        }
    }
}

@MainActor
@Suite("Hover: a change a frame's own hit regions make is drawn before the next input")
struct HoverOwedFrameTests {
    @Test("The frame a reshape under the resting pointer owes is drawn before a key is handled")
    func owedFrameDrawnBeforeTheKey() throws {
        let app = TestApp(LitRowApp(), width: 40, height: 10)
        app.frame(atNanos: 16_666_667)
        let row = try #require(app.screen.location(of: "row dark"))
        // The pointer rests on the blank line under the row.
        app.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y + 1))
        app.frame(atNanos: 33_333_333)
        // A key slides the row under it; the frame that draws the slide enters
        // it as it publishes its regions, after it is drawn.
        app.send(KeyEvent(key: .character("n")))
        app.frame(atNanos: 50_000_000)
        #expect(app.screen.contains("row dark"), "precondition: the hover is entered after the frame drew")
        // The next key — one nothing takes — comes after the frame that shows it.
        let framesBefore = app.headless.framesDrawn
        app.send(KeyEvent(key: .character("z")))
        #expect(app.headless.framesDrawn == framesBefore + 1, "no frame was drawn before the key")
        #expect(app.screen.contains("row LIT"), "the hover entered after the frame was not drawn: \(app.screen)")
    }

    @Test("A frame that owes none draws none before the key")
    func noOwedFrameNoExtraFrame() {
        let app = TestApp(LitRowApp(), width: 40, height: 10)
        app.frame(atNanos: 16_666_667)
        let framesBefore = app.headless.framesDrawn
        app.send(KeyEvent(key: .character("z")))
        #expect(app.headless.framesDrawn == framesBefore)
    }

    @Test("The run loop holds its reading for the owed frame, within the backlog limit")
    func runLoopHoldsForTheOwedFrame() {
        var hold = ActivationHold()
        let stopped = hold.frameOwesAnother(atNanos: 1_000)
        #expect(stopped && hold.isHolding)
        let waited = hold.frameDrawn()
        #expect(waited && !hold.isHolding)
        // A frame owing one on every frame would starve the input: past the
        // limit the reading goes on.
        let past = hold.frameOwesAnother(atNanos: 1_000 + ActivationHold.backlogLimitNanos + 1)
        #expect(!past && !hold.isHolding)
    }
}
