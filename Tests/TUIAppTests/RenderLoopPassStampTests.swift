//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoopPassStampTests.swift
//
//  The run loop draws each frame as one render pass that every `@State` made
//  in it notes, the app's body and the views it makes included: what tells
//  an object made with a view value from one made before (lane DYNVCLAIM).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUITestSupport
@testable import TUIView

/// The passes noted, in the order noted.
@MainActor
private final class PassLog {
    /// The pass the app's body read, each frame.
    var appBody: [UInt32] = []
    /// The pass a `@State` made in a view's body noted, each frame.
    var made: [UInt32] = []
}

/// A view whose body makes a `@State` and notes the pass it noted, read
/// through its private backing (`StateBacking.createdIn`).
private struct StateMakingView: View {
    let log: PassLog

    var body: some View {
        let state = State(wrappedValue: 0)
        log.made.append((Mirror(reflecting: state).descendant("backing") as? StateBacking<Int>)?.createdIn ?? .max)
        return Text(verbatim: "made")
    }
}

/// An app whose body notes the pass it is evaluated in, in a log of its own:
/// not a static one, which a second run of the test in the process would find
/// holding the first run's passes.
private struct PassNotingApp: App {
    let log: PassLog

    init() { log = PassLog() }

    init(log: PassLog) { self.log = log }

    var body: some Scene {
        log.appBody.append(StateRegistration.renderPass)
        return WindowGroup { StateMakingView(log: log) }
    }
}

@MainActor
@Suite("Render loop pass stamps")
struct RenderLoopPassStampTests {
    /// Each frame is one pass to its end: the app's body and a view's body
    /// both read it, and the next frame is another. Run twice, as a repeated
    /// run of the suite in one process runs it: each run reads its own app's
    /// passes.
    @Test(
        "A frame the run loop draws is one render pass, which a @State made in a view's body notes",
        arguments: 1...2)
    func frameBindsItsRenderPass(run _: Int) {
        let log = PassLog()
        let app = HeadlessApp(PassNotingApp(log: log), width: 20, height: 4)
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        #expect(!log.appBody.isEmpty && !log.appBody.contains(0), "app body: \(log.appBody)")
        #expect(!log.made.isEmpty && !log.made.contains(0), "made: \(log.made)")
        #expect(Set(log.appBody) == Set(log.made), "one pass per frame: \(log.appBody) \(log.made)")
        #expect(Set(log.made).count == 2, "a pass per frame: \(log.made)")
    }
}
