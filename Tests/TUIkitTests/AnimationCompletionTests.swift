//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationCompletionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Records which completions ran, in order.
@MainActor
private final class Fired {
    var names: [String] = []
}

/// Renders a view frame by frame as the run loop does around a change: the
/// change's completions handed to the pass that shows it, and the tracker told
/// when each pass ends.
@MainActor
private final class Frames {
    var context = makeRenderContext(width: 20, height: 3)
    var storage: StateStorage { context.environment.stateStorage! }

    init() {
        context.environment.canAnimate = true
    }

    func draw<V: View>(
        _ view: V, atMillis millis: Int, under transaction: Transaction = Transaction(),
        placing completions: [AnimationCompletion] = []
    ) {
        let now = Int64(millis) * 1_000_000
        context.environment.frameNowNanos = now
        context.environment.transaction = transaction
        storage.beginRenderPass()
        storage.animationCompletions.beginPass(placing: completions)
        _ = renderToBuffer(view, context: context)
        storage.endRenderPass()
        storage.animationCompletions.endPass(at: now, animations: storage.animations)
    }
}

/// A transaction animating with `animation`, carrying one completion that
/// records `name` in `fired`, and that completion.
@MainActor
private func animated(
    _ animation: Animation?, criteria: AnimationCompletionCriteria = .logicallyComplete,
    _ name: String, into fired: Fired
) -> (Transaction, [AnimationCompletion]) {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: criteria) { fired.names.append(name) }
    return (transaction, transaction.completions)
}

@MainActor
@Suite("Animation completions")
struct AnimationCompletionTests {

    // MARK: - The change and its body

    @Test("A body that changes nothing runs its completion as soon as it returns")
    func unclaimedFiresAfterBody() {
        var ran = false
        withAnimation(.linear(duration: 1)) {
            #expect(!ran)
        } completion: {
            ran = true
        }
        #expect(ran)
    }

    @Test("A body that changes state leaves its completion to the render that shows it")
    func claimedWaitsForTheRender() {
        let state = AppState()
        var ran = false
        withAnimation(.linear(duration: 1)) {
            state.setNeedsRender()
        } completion: {
            ran = true
        }
        #expect(!ran)
        let pending = state.consumePendingCompletions()
        #expect(pending.count == 1)
        #expect(state.consumePendingCompletions().isEmpty, "consumed once")
    }

    @Test("Every change in a frame keeps its completion, though only the last one's transaction renders")
    func coalescedChangesKeepEveryCompletion() {
        let state = AppState()
        withAnimation(.linear(duration: 1)) { state.setNeedsRender() } completion: {}
        withAnimation(.easeIn(duration: 2)) { state.setNeedsRender() } completion: {}
        #expect(state.consumePendingCompletions().count == 2)
        #expect(state.consumePendingTransaction()?.animation == .easeIn(duration: 2))
    }

    @Test("A completion the enclosing call carries is the enclosing call's to fire")
    func nestedTransactionDoesNotFireTheOuterCompletion() {
        let state = AppState()
        var ran = false
        withAnimation(.linear(duration: 1)) {
            withTransaction(\.isContinuous, true) {}
            #expect(!ran, "the inner call made no change, but the completion is not its own")
            state.setNeedsRender()
        } completion: {
            ran = true
        }
        #expect(!ran)
    }

    // MARK: - The render that shows it

    @Test("A change that starts no animation completes when its pass ends")
    func noAnimationCompletesAtTheEndOfThePass() {
        let fired = Fired()
        let frames = Frames()
        frames.draw(Text("x").opacity(1), atMillis: 0)
        let (transaction, completions) = animated(.linear(duration: 1), "done", into: fired)
        frames.draw(Text("x").opacity(1), atMillis: 10, under: transaction, placing: completions)
        #expect(fired.names == ["done"])
    }

    @Test("A curve completes when it ends, and only once")
    func curveCompletesAtItsEnd() {
        let fired = Fired()
        let frames = Frames()
        frames.draw(Text("x").opacity(1), atMillis: 0)
        let (transaction, completions) = animated(.linear(duration: 1), "done", into: fired)
        frames.draw(Text("x").opacity(0), atMillis: 100, under: transaction, placing: completions)
        frames.draw(Text("x").opacity(0), atMillis: 600)
        #expect(fired.names.isEmpty)
        frames.draw(Text("x").opacity(0), atMillis: 1100)
        #expect(fired.names == ["done"])
        frames.draw(Text("x").opacity(0), atMillis: 1200)
        #expect(fired.names == ["done"], "exactly once")
    }

    @Test("A spring logically completes at its pace and is removed once it settles")
    func springLogicalBeforeRemoved() throws {
        let fired = Fired()
        let frames = Frames()
        let spring = Animation.spring(duration: 0.5, bounce: 0)
        let settle = try #require(spring.totalDuration)
        #expect(spring.logicalCompletionDuration == 0.5)
        #expect(settle > 0.6, "a spring settles well after its pace (\(settle) s)")

        frames.draw(Text("x").opacity(1), atMillis: 0)
        var transaction = Transaction(animation: spring)
        transaction.addAnimationCompletion { fired.names.append("logical") }
        transaction.addAnimationCompletion(criteria: .removed) { fired.names.append("removed") }
        frames.draw(Text("x").opacity(0), atMillis: 0, under: transaction, placing: transaction.completions)
        frames.draw(Text("x").opacity(0), atMillis: 520)
        #expect(fired.names == ["logical"])
        frames.draw(Text("x").opacity(0), atMillis: Int(settle * 1000) + 20)
        #expect(fired.names == ["logical", "removed"])
    }

    @Test("A retarget delays removal but not logical completion")
    func retargetDelaysRemovalOnly() {
        let fired = Fired()
        let frames = Frames()
        frames.draw(Text("x").opacity(1), atMillis: 0)
        var first = Transaction(animation: .linear(duration: 1))
        first.addAnimationCompletion { fired.names.append("logical") }
        first.addAnimationCompletion(criteria: .removed) { fired.names.append("removed") }
        frames.draw(Text("x").opacity(0), atMillis: 0, under: first, placing: first.completions)
        // Half-way there, the value is sent back, for another second.
        frames.draw(Text("x").opacity(1), atMillis: 500, under: Transaction(animation: .linear(duration: 1)))
        frames.draw(Text("x").opacity(1), atMillis: 1050)
        #expect(fired.names == ["logical"], "the first change's animation has logically completed")
        frames.draw(Text("x").opacity(1), atMillis: 1550)
        #expect(fired.names == ["logical", "removed"])
    }

    @Test("An animation removed with its view is complete")
    func removedViewCompletes() {
        let fired = Fired()
        let frames = Frames()
        frames.draw(Text("x").opacity(1), atMillis: 0)
        let forever = Animation.linear(duration: 1).repeatForever()
        let (transaction, completions) = animated(forever, criteria: .removed, "gone", into: fired)
        frames.draw(Text("x").opacity(0), atMillis: 0, under: transaction, placing: completions)
        frames.draw(Text("x").opacity(0), atMillis: 5000)
        #expect(fired.names.isEmpty, "a repeating animation on screen never completes")
        frames.draw(EmptyView(), atMillis: 5100)
        #expect(fired.names == ["gone"])
    }

    @Test("A departing view's removal holds the completion until it has gone")
    func departureHoldsTheCompletion() {
        let fired = Fired()
        let frames = Frames()
        let present: Text? = Text("XX")
        let absent: Text? = nil
        frames.draw(present.map { $0.transition(.opacity) }, atMillis: 0)
        let (transaction, completions) = animated(.linear(duration: 1), "gone", into: fired)
        frames.draw(absent.map { $0.transition(.opacity) }, atMillis: 100, under: transaction, placing: completions)
        frames.draw(absent.map { $0.transition(.opacity) }, atMillis: 600)
        #expect(fired.names.isEmpty)
        frames.draw(absent.map { $0.transition(.opacity) }, atMillis: 1150)
        #expect(fired.names == ["gone"])
    }

    // MARK: - Logical completion of an animation

    @Test("logicallyComplete(after:) brings logical completion forward, never past the end")
    func logicallyCompleteAfter() {
        #expect(Animation.linear(duration: 1).logicalCompletionDuration == 1)
        #expect(Animation.linear(duration: 1).logicallyComplete(after: 0.25).logicalCompletionDuration == 0.25)
        #expect(Animation.linear(duration: 1).logicallyComplete(after: 3).logicalCompletionDuration == 1)
        #expect(Animation.linear(duration: 1).logicallyComplete(after: 0.5).speed(2).logicalCompletionDuration == 0.25)
        #expect(Animation.linear(duration: 1).repeatForever().logicalCompletionDuration == nil)
        #expect(
            Animation.linear(duration: 1).logicallyComplete(after: 0.5).description
                == "linear(duration: 1.0).logicallyComplete(after: 0.5)")
    }
}
