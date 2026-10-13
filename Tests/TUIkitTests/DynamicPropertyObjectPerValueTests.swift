//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectPerValueTests.swift
//
//  An object made with each value of the view that holds it (session notes
//  DYNV2/notes.md §4.11) is told from one made before by when its `@State`
//  was made: each `@State` notes the render pass it was made in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What each body hands out.
@MainActor
private final class PassTaps {
    /// The pass each `@State` a body made noted, in the order made.
    var made: [UInt32] = []
}

/// The render pass the `@State` `state` noted when it was made
/// (`StateBacking.createdIn`), read through its private backing.
private func createdIn<Value>(_ state: State<Value>) -> UInt32? {
    (Mirror(reflecting: state).descendant("backing") as? StateBacking<Value>)?.createdIn
}

/// A view whose body makes a `@State`, as a view value made there makes
/// one, and notes the pass it noted.
private struct StateMakingView: View {
    let taps: PassTaps

    var body: some View {
        taps.made.append(createdIn(State(wrappedValue: 0)) ?? .max)
        return Text(verbatim: "made")
    }
}

@MainActor
@Suite("DynamicProperty objects made with a view value")
struct DynamicPropertyObjectPerValueTests {

    /// One frame as the render loop draws it: the pass begun, the view made
    /// and drawn in it (`StateStorage.inRenderPass(_:)`), the pass ended.
    private func frame<V: View>(_ view: @autoclosure () -> V, _ tui: TUIContext) {
        let context = RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: tui)
        tui.renderCache.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        _ = tui.stateStorage.inRenderPass { renderToBuffer(view(), context: context) }
    }

    /// What an object made with a view value is told by (lane DYNVCLAIM): a
    /// `@State` made in a frame notes that frame's pass, each frame its own;
    /// one made outside every frame, `0`.
    @Test("A @State made in a frame notes the frame's render pass, and one made outside every frame notes none")
    func stateNotesTheRenderPassItWasMadeIn() {
        let tui = TUIContext()
        let taps = PassTaps()
        frame(StateMakingView(taps: taps), tui)
        let first = tui.stateStorage.currentPass
        frame(StateMakingView(taps: taps), tui)
        let second = tui.stateStorage.currentPass
        #expect(first != 0)
        #expect(second != first)
        #expect(taps.made == [first, second])
        #expect(createdIn(State(wrappedValue: 0)) == 0, "made outside every frame")
    }

    /// A render no pass is bound around makes every `@State` note `0`, as
    /// one made in an event handler does: such a render takes every object
    /// for one made before it.
    @Test("A @State made in a render no pass is bound around notes no pass")
    func stateMadeInAnUnboundRenderNotesNoPass() {
        let tui = TUIContext()
        let taps = PassTaps()
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(
            StateMakingView(taps: taps), context: RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: tui))
        tui.stateStorage.endRenderPass()
        #expect(taps.made == [0])
    }

    /// The serial is the process's, not the storage's: a pass of one context
    /// is never another's, so a `@State` made in one context's frame is never
    /// taken for one made in another's.
    @Test("Two contexts' render passes never share a serial")
    func twoContextsNeverShareAPass() {
        let one = TUIContext()
        let other = TUIContext()
        var seen: Set<UInt32> = []
        for _ in 0..<3 {
            one.stateStorage.beginRenderPass()
            other.stateStorage.beginRenderPass()
            seen.insert(one.stateStorage.currentPass)
            seen.insert(other.stateStorage.currentPass)
            let made = one.stateStorage.inRenderPass { createdIn(State(wrappedValue: 0)) }
            #expect(made == one.stateStorage.currentPass)
            #expect(made != other.stateStorage.currentPass)
            one.stateStorage.endRenderPass()
            other.stateStorage.endRenderPass()
        }
        #expect(seen.count == 6)
        #expect(!seen.contains(0))
    }
}
