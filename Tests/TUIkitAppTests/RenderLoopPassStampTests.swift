//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoopPassStampTests.swift
//
//  The run loop draws each frame as one render pass that every `@State` made
//  in it notes, the app's body and the views it makes included: what tells
//  an object made with a view value from one made before (lane DYNVCLAIM).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitTestSupport
@testable import TUIkitView

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

/// An app whose body notes the pass it is evaluated in.
private struct PassNotingApp: App {
    @MainActor static let log = PassLog()

    init() {}

    var body: some Scene {
        Self.log.appBody.append(StateRegistration.renderPass)
        return WindowGroup { StateMakingView(log: Self.log) }
    }
}

@MainActor
@Suite("Render loop pass stamps")
struct RenderLoopPassStampTests {
    /// Each frame is one pass to its end: the app's body and a view's body
    /// both read it, and the next frame is another.
    @Test("A frame the run loop draws is one render pass, which a @State made in a view's body notes")
    func frameBindsItsRenderPass() {
        let app = HeadlessApp(PassNotingApp(), width: 20, height: 4)
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        let log = PassNotingApp.log
        #expect(!log.appBody.isEmpty && !log.appBody.contains(0), "app body: \(log.appBody)")
        #expect(!log.made.isEmpty && !log.made.contains(0), "made: \(log.made)")
        #expect(Set(log.appBody) == Set(log.made), "one pass per frame: \(log.appBody) \(log.made)")
        #expect(Set(log.made).count == 2, "a pass per frame: \(log.made)")
    }
}
