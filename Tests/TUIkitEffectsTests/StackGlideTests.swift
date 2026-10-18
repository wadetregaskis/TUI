//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackGlideTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// The probe's column, in cells: a row above, four rows that come and go, and
/// a row below whose place is what SwiftUI animates (`plan/fb16/FB16Probe.swift`).
private struct Column: View {
    let showing: Bool
    let transition: AnyTransition
    var lifted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A")
            if showing {
                VStack(alignment: .leading, spacing: 0) {
                    Text("X")
                    Text("X")
                    Text("X")
                    Text("X")
                }
                .zIndex(lifted ? 1 : 0)
                .transition(transition)
            }
            Text("B")
        }
    }
}

/// The same across a row.
private struct Row: View {
    let showing: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("A")
            if showing { Text("XXXX").transition(.opacity) }
            Text("B")
        }
    }
}

/// Layers whose alignment moves when a wider one comes and goes, the one
/// that stays drawn over it.
private struct Layers: View {
    let showing: Bool

    var body: some View {
        ZStack {
            if showing { Text("XXXXX").transition(.opacity) }
            Text("A")
        }
    }
}

/// A row laid out by a `Layout`, not a stack.
private struct LaidOutRow: View {
    let showing: Bool

    var body: some View {
        HStackLayout(spacing: 0) {
            Text("A")
            if showing { Text("XXXX").transition(.opacity) }
            Text("B")
        }
    }
}

/// A view drawn frame by frame as the run loop draws it: the change's
/// transaction in force for the one pass that shows the change, and none on the
/// frames after it, which only move the clock on.
@MainActor
private final class Frames {
    var context = makeRenderContext(width: 12, height: 12)
    var storage: StateStorage { context.environment.stateStorage! }

    init(reduceMotion: Bool = false) {
        context.environment.canAnimate = true
        context.environment.accessibilityReduceMotion = reduceMotion
    }

    /// `view` at `millis`, under `animation` when the frame carries a change,
    /// with what is drawn past each stack drawn in, styling stripped.
    func draw<V: View>(_ view: V, atMillis millis: Int, animating animation: Animation? = nil) -> [String] {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: animation)
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context).withLayersDrawn().lines.map(\.stripped)
    }

    /// The row `glyph` is drawn on, or `nil`.
    func row(of glyph: String, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains(glyph) }
    }
}

@MainActor
@Suite("Siblings glide when a view comes and goes")
struct StackGlideTests {

    // MARK: - Insertion

    /// The probe: the view below an inserted one moves from its old place to
    /// its new one with the change's animation, whatever the transition —
    /// `samples.txt`, every column, 187 → 202 → 218 → 247 over 8 s.
    @Test("A sibling below an insertion glides down with the change", arguments: [false, true])
    func insertionGlides(identity: Bool) {
        let transition: AnyTransition = identity ? .identity : .opacity
        let frames = Frames()
        _ = frames.draw(Column(showing: false, transition: transition), atMillis: 0)
        let start = frames.draw(
            Column(showing: true, transition: transition), atMillis: 1000, animating: .linear(duration: 1))
        #expect(frames.row(of: "B", in: start) == 1, "the layout is new, but B starts where it was: \(start)")
        let half = frames.draw(Column(showing: true, transition: transition), atMillis: 1500)
        #expect(frames.row(of: "B", in: half) == 3, "half-way down: \(half)")
        let end = frames.draw(Column(showing: true, transition: transition), atMillis: 2000)
        #expect(frames.row(of: "B", in: end) == 5, "arrived: \(end)")
        #expect(end.prefix(6) == ["A", "X", "X", "X", "X", "B"])
    }

    @Test("A sibling after an insertion in a row glides across")
    func rowInsertionGlides() {
        let frames = Frames()
        _ = frames.draw(Row(showing: false), atMillis: 0)
        #expect(frames.draw(Row(showing: true), atMillis: 1000, animating: .linear(duration: 1))[0].hasPrefix("AB"))
        #expect(frames.draw(Row(showing: true), atMillis: 1500)[0].hasPrefix("AXXB"))
        #expect(frames.draw(Row(showing: true), atMillis: 2000)[0].hasPrefix("AXXXXB"))
    }

    /// A `ZStack` places its layers by computed offsets too: the one that
    /// stays re-centres in the wider frame by gliding there.
    @Test("A layer re-centred by an insertion glides there, and back as the layer leaves")
    func zStackLayersGlide() {
        let frames = Frames()
        _ = frames.draw(Layers(showing: false), atMillis: 0)
        #expect(frames.draw(Layers(showing: true), atMillis: 1000, animating: .linear(duration: 1))[0] == "AXXXX")
        #expect(frames.draw(Layers(showing: true), atMillis: 1500)[0] == "XAXXX")
        #expect(frames.draw(Layers(showing: true), atMillis: 2000)[0] == "XXAXX")
        // The frame is one cell at once; the wide layer fades where it was,
        // beneath the one gliding back.
        #expect(frames.draw(Layers(showing: false), atMillis: 3000, animating: .linear(duration: 1))[0] == "XXAXX")
        #expect(frames.draw(Layers(showing: false), atMillis: 3500)[0] == "XAXXX")
        #expect(frames.draw(Layers(showing: false), atMillis: 4100)[0] == "A")
    }

    @Test("A subview a layout moves glides there")
    func layoutSubviewsGlide() {
        let frames = Frames()
        _ = frames.draw(LaidOutRow(showing: false), atMillis: 0)
        #expect(frames.draw(LaidOutRow(showing: true), atMillis: 1000, animating: .linear(duration: 1))[0].hasPrefix("AB"))
        #expect(frames.draw(LaidOutRow(showing: true), atMillis: 1500)[0].hasPrefix("AXXB"))
        #expect(frames.draw(LaidOutRow(showing: true), atMillis: 2000)[0] == "AXXXXB")
    }

    @Test("An unanimated insertion moves its siblings at once")
    func unanimatedInsertionJumps() {
        let frames = Frames()
        _ = frames.draw(Column(showing: false, transition: .opacity), atMillis: 0)
        let lines = frames.draw(Column(showing: true, transition: .opacity), atMillis: 1000)
        #expect(frames.row(of: "B", in: lines) == 5)
    }

    // MARK: - Removal

    /// The mirror image: the layout closes up at once, the removed view plays
    /// its removal where it was, and the view below glides up over it.
    @Test("A sibling below a removal glides up while the view leaves where it was")
    func removalGlides() {
        let frames = Frames()
        _ = frames.draw(Column(showing: true, transition: .opacity), atMillis: 0)
        let start = frames.draw(
            Column(showing: false, transition: .opacity), atMillis: 1000, animating: .linear(duration: 1))
        #expect(start.prefix(6) == ["A", "X", "X", "X", "X", "B"], "nothing has moved yet: \(start)")
        let half = frames.draw(Column(showing: false, transition: .opacity), atMillis: 1500)
        #expect(frames.row(of: "B", in: half) == 3, "half-way up, over the view leaving: \(half)")
        #expect(half.prefix(5) == ["A", "X", "X", "B", "X"], "the view leaving is still drawn: \(half)")
        let end = frames.draw(Column(showing: false, transition: .opacity), atMillis: 2000)
        #expect(end.prefix(2) == ["A", "B"], "closed up: \(end)")
    }

    /// The room goes on the frame the view does: what the stack lays out is
    /// two rows from the first frame, and what it draws past them is the
    /// glide.
    @Test("A removal gives its room back at once")
    func removalLeavesTheLayout() {
        let frames = Frames()
        _ = frames.draw(Column(showing: true, transition: .opacity), atMillis: 0)
        frames.context.environment.frameNowNanos = 1_000_000_000
        frames.context.environment.transaction = Transaction(animation: .linear(duration: 1))
        frames.storage.beginRenderPass()
        let size = measureChild(Column(showing: false, transition: .opacity), proposal: .unspecified, context: frames.context)
        let buffer = renderToBuffer(Column(showing: false, transition: .opacity), context: frames.context)
        frames.storage.endRenderPass()
        #expect(size.height == 2)
        #expect(buffer.lines.count == 2)
    }

    /// SwiftUI draws the view leaving beneath its siblings (the removed view's
    /// layer is the first in its column in every removal sample), and a
    /// `.zIndex` is how an app lifts it, as there.
    @Test("A view leaving is drawn beneath its siblings unless its z-index lifts it", arguments: [false, true])
    func departureStacking(lifted: Bool) {
        let frames = Frames()
        _ = frames.draw(Column(showing: true, transition: .opacity, lifted: lifted), atMillis: 0)
        _ = frames.draw(
            Column(showing: false, transition: .opacity, lifted: lifted), atMillis: 1000,
            animating: .linear(duration: 1))
        let half = frames.draw(Column(showing: false, transition: .opacity, lifted: lifted), atMillis: 1500)
        #expect(half[3] == (lifted ? "X" : "B"), "\(half)")
    }

    @Test("Held, a removal keeps its room until it has played, then closes up at once")
    func heldRemovalKeepsItsRoom() {
        let frames = Frames()
        func column(_ showing: Bool) -> some View {
            Column(showing: showing, transition: .opacity).transitionSpace(.held)
        }
        _ = frames.draw(column(true), atMillis: 0)
        _ = frames.draw(column(false), atMillis: 1000, animating: .linear(duration: 1))
        let half = frames.draw(column(false), atMillis: 1500)
        #expect(frames.row(of: "B", in: half) == 5, "standing still while the view leaves: \(half)")
        let after = frames.draw(column(false), atMillis: 2100)
        #expect(frames.row(of: "B", in: after) == 1, "closed up once it had gone: \(after)")
    }

    // MARK: - Interruption, reduce motion

    /// A change mid-glide takes over from where the picture is: a linear
    /// animation does not merge, so the earlier glide runs on beside the new
    /// one (decisions O3), and nothing jumps on the frame of the change.
    @Test("A removal half-way through an insertion carries on from where the sibling is")
    func interruptionStartsFromThePicture() {
        let frames = Frames()
        _ = frames.draw(Column(showing: false, transition: .opacity), atMillis: 0)
        _ = frames.draw(Column(showing: true, transition: .opacity), atMillis: 1000, animating: .linear(duration: 1))
        #expect(frames.row(of: "B", in: frames.draw(Column(showing: true, transition: .opacity), atMillis: 1500)) == 3)
        let turned = frames.draw(
            Column(showing: false, transition: .opacity), atMillis: 1500, animating: .linear(duration: 1))
        #expect(frames.row(of: "B", in: turned) == 3, "no jump on the frame of the change: \(turned)")
        let end = frames.draw(Column(showing: false, transition: .opacity), atMillis: 3000)
        #expect(frames.row(of: "B", in: end) == 1, "it arrives where the new layout puts it: \(end)")
    }

    /// Reduce motion holds still what moves in X and Y (owner decision
    /// A-D3M-1): a glide is that. The same change without it glides.
    @Test("Under reduce motion the siblings jump", arguments: [false, true])
    func reduceMotionJumps(reduceMotion: Bool) {
        let frames = Frames(reduceMotion: reduceMotion)
        _ = frames.draw(Column(showing: false, transition: .opacity), atMillis: 0)
        let lines = frames.draw(
            Column(showing: true, transition: .opacity), atMillis: 1000, animating: .linear(duration: 1))
        #expect(frames.row(of: "B", in: lines) == (reduceMotion ? 5 : 1), "\(lines)")
    }

    // MARK: - What a settled stack pays

    /// A stack whose layout does not change asks the animation store nothing:
    /// its children's placements are compared with what it remembers, and
    /// that is all — under an animated transaction too.
    @Test("A stack that is not moving keeps nothing in the animation store")
    func settledStackAsksNothing() {
        let frames = Frames()
        _ = frames.draw(Column(showing: true, transition: .opacity), atMillis: 0)
        // The transition's own arrival is all the store holds.
        let held = frames.storage.animations.count
        _ = frames.draw(Column(showing: true, transition: .opacity), atMillis: 1000, animating: .linear(duration: 1))
        #expect(frames.storage.animations.count == held)
        #expect(frames.storage.placements.count != .zero)
    }

    /// A glide's motion is a function of the clock, so nothing may serve the
    /// stack's buffer from a memo while it moves; the run loop goes on drawing
    /// until it lands.
    @Test("A glide keeps the run loop drawing until it lands")
    func glideIsLive() {
        let frames = Frames()
        _ = frames.draw(Column(showing: false, transition: .identity), atMillis: 0)
        _ = frames.draw(Column(showing: true, transition: .identity), atMillis: 1000, animating: .linear(duration: 1))
        // The transition's own arrival, and B's glide.
        let moving = frames.storage.animations.count
        #expect(frames.storage.animations.hasLiveAnimations(at: 1_500_000_000))
        _ = frames.draw(Column(showing: true, transition: .identity), atMillis: 2000)
        #expect(!frames.storage.animations.hasLiveAnimations(at: 2_000_000_000))
        _ = frames.draw(Column(showing: true, transition: .identity), atMillis: 2100)
        #expect(frames.storage.animations.count == moving - 1, "a landed glide is forgotten")
    }
}
