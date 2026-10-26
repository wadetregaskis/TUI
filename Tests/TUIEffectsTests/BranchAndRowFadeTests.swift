//  🖥️ TUI — A Terminal UI framework for Swift
//  BranchAndRowFadeTests.swift
//
//  The default transition for what is not an `if`: the branch an `if`/`else`
//  flips to, a `switch`'s case, a `ForEach`'s row. Each fades in where it
//  lands while the views around it glide, as SwiftUI's do with no
//  `.transition` written (measured, `Tools/SwiftUIProbes/Transitions/tr1.out`
//  T1–T3 and T8). The one leaving goes at once, where SwiftUI's fades out: the
//  owner's fallback, fading in only, since keeping every child's picture for
//  the fade-out cost too much with nothing animating (decisions TR2PERF). One
//  with a transition of its own plays it on the way out.
//
//  A fade is an opacity claim on the cells, and where two pictures overlap
//  the compositor resolves the top one's claim against the cells beneath:
//  its glyph shows from half-way, the one beneath until then. So these read
//  the glyphs drawn, and the claims left where nothing is beneath.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport

/// An `if`/`else` in a column, above a row that stays.
private struct Flip: View {
    let first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if first { Text("XXXX") } else { Text("YY") }
            Text("----")
        }
    }
}

/// A `switch` of three cases in a column.
private struct Cases: View {
    let which: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch which {
            case 0: Text("XXXX")
            case 1: Text("ZZZ")
            default: Text("YY")
            }
            Text("----")
        }
    }
}

/// A loop's rows in a column, above a row that stays.
private struct Rows: View {
    let ids: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ids, id: \.self) { id in Text(String(repeating: "\(id)", count: 4)) }
            Text("----")
        }
    }
}

/// A loop's rows below a row that stays, each with a transition of its own.
private struct SlidingRows: View {
    let ids: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            ForEach(ids, id: \.self) { id in
                Text(String(repeating: "\(id)", count: 4)).transition(.move(edge: .trailing))
            }
        }
    }
}

/// A transition that runs under a second of its own, whatever the change.
private let timedMove = AnyTransition.move(edge: .trailing).animation(.linear(duration: 1))

/// A loop's rows below a row that stays, each with a transition that names
/// its own animation.
private struct TimedRows: View {
    let ids: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            ForEach(ids, id: \.self) { id in Text(String(repeating: "\(id)", count: 4)).transition(timedMove) }
        }
    }
}

/// Where a branch with a transition naming its own animation stands.
enum TimedBranchShape: Sendable {
    /// An `if`/`else` the stack takes apart.
    case stacked
    /// An `if`/`else` that is a view's whole body, drawn whole.
    case whole
    /// The first branch alone, as an `if` whose `nil` plays the removal.
    case ifAlone
}

/// An `if`/`else` below a row that stays, whose first branch has a
/// transition that names its own animation.
private struct TimedFlip: View {
    let first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            if first { Text("XXXX").transition(timedMove) } else { Text("YY") }
        }
    }
}

/// ``TimedFlip`` with its `if`/`else` as a view's whole body, drawn whole.
private struct TimedWholeFlip: View {
    let first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            TimedWholeBody(first: first)
        }
    }
}

/// ``TimedWholeFlip``'s view.
private struct TimedWholeBody: View {
    let first: Bool

    var body: some View {
        if first { Text("XXXX").transition(timedMove) } else { Text("YY") }
    }
}

/// ``TimedFlip``'s first branch alone, as an `if`.
private struct TimedIf: View {
    let first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            if first { Text("XXXX").transition(timedMove) }
        }
    }
}

/// A view an `if` holds below a row that stays, and what that view holds
/// changing while the `if` is empty: an `if`/`else` drawn whole, a stack's
/// rows, an `if` of its own.
private struct Hidden: View {
    let showing: Bool
    let inner: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            if showing { HiddenContent(inner: inner) }
        }
    }
}

/// ``Hidden``'s view: its own `if`/`else`, a column of rows and an `if`.
private struct HiddenContent: View {
    let inner: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WholeBody(first: inner)
            Rows(ids: inner ? [1, 2] : [1])
            HStack(spacing: 0) {
                Text("<")
                if inner { Text("CCCC") }
                Text(">")
            }
        }
    }
}

/// An `if` holding two views, which has no one slot to keep.
private struct Several: View {
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("----")
            if showing {
                Text("AAAA")
                Text("BBBB")
            }
        }
    }
}

/// What an `if` holds that, in a stack, it hands the stack rather than
/// holding it itself — so the stack, not the `if`, sees it go.
enum HandedOverShape: String, CaseIterable, Sendable {
    /// `if a { Group { X } }`.
    case group
    /// `if a { Group { X }.foregroundStyle(.red) }`: a modifier on the
    /// structure that draws nothing.
    case styledGroup
    /// `if a { Group { X }.padding() }`: one that draws.
    case paddedGroup
    /// `if a { if c { X } else { Y } }`.
    case conditional
    /// `(a ? X : nil).id(k)`: `.id` written on the `if`.
    case identified
}

/// `shape` in a column, below a row that stays.
private struct HandedOverInStack: View {
    let showing: Bool
    let shape: HandedOverShape
    /// Read by the shape with a second condition, so its `if` is a real one.
    let other = true

    var body: some View {
        switch shape {
        case .group:
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Group { Text("XXXX") } }
            }
        case .styledGroup:
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Group { Text("XXXX") }.foregroundStyle(.red) }
            }
        case .paddedGroup:
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { Group { Text("XXXX") }.padding(.leading, 2) }
            }
        case .conditional:
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                if showing { if other { Text("XXXX") } else { Text("never") } }
            }
        case .identified:
            VStack(alignment: .leading, spacing: 0) {
                Text("----")
                (showing ? Text("XXXX") : nil).id("k")
            }
        }
    }
}

/// `shape` rendered directly, as a view's whole `body`.
private struct HandedOverDirectly: View {
    let showing: Bool
    let shape: HandedOverShape
    /// Read by the shape with a second condition, so its `if` is a real one.
    let other = true

    var body: some View {
        switch shape {
        case .group: if showing { Group { Text("XXXX") } }
        case .styledGroup: if showing { Group { Text("XXXX") }.foregroundStyle(.red) }
        case .paddedGroup: if showing { Group { Text("XXXX") }.padding(.leading, 2) }
        case .conditional: if showing { if other { Text("XXXX") } else { Text("never") } }
        case .identified: (showing ? Text("XXXX") : nil).id("k")
        }
    }
}

/// A view whose whole body is an `if`/`else`: drawn whole, not taken apart.
private struct WholeBody: View {
    let first: Bool

    var body: some View {
        if first { Text("XXXX") } else { Text("YY") }
    }
}

/// A view drawn frame by frame as the run loop draws it: the change's
/// transaction in force for the one pass that shows the change.
@MainActor
private final class Frames {
    var context = makeRenderContext(width: 12, height: 8)
    var storage: StateStorage { context.environment.stateStorage! }

    init(reduceMotion: Bool = false) {
        context.environment.canAnimate = true
        context.environment.accessibilityReduceMotion = reduceMotion
    }

    /// `view` at `millis`, under a one-second linear change when `changed`.
    func buffer<V: View>(_ view: V, atMillis millis: Int, changed: Bool = false) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: changed ? .linear(duration: 1) : nil)
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }

    /// The rows drawn, what lies past each stack drawn in, styling and
    /// trailing blanks stripped.
    func draw<V: View>(_ view: V, atMillis millis: Int, changed: Bool = false) -> [String] {
        buffer(view, atMillis: millis, changed: changed).withLayersDrawn().lines.map(\.stripped).map {
            String($0.reversed().drop { $0 == " " }.reversed())
        }
    }
}

/// The strengths of the fades a frame still carries, its layers' included.
private func fades(_ buffer: FrameBuffer) -> [Double] {
    var found = buffer.opacityRegions.map { ($0.opacity * 100).rounded() / 100 }
    for layer in buffer.overlays { found += fades(layer.content) }
    return found
}

@MainActor
@Suite("A branch, a case and a row fade in by default, and go at once")
struct BranchAndRowFadeTests {

    // MARK: - A branch flip

    /// The new branch fades in where it lands; the one it replaces is gone
    /// on the frame of the change, where SwiftUI's fades out beneath it.
    @Test("An if/else whose branch flips fades the new branch in, and the old one goes at once")
    func branchFlipFades() {
        let frames = Frames()
        _ = frames.draw(Flip(first: true), atMillis: 0)
        #expect(frames.draw(Flip(first: false), atMillis: 1000, changed: true) == ["YY", "----"], "the old gone")
        let late = frames.buffer(Flip(first: false), atMillis: 1750)
        #expect(late.withLayersDrawn().lines.map(\.stripped).first == "YY  ", "nothing of the old")
        #expect(fades(late) == [0.75], "the new fading in: \(fades(late))")
        #expect(fades(frames.buffer(Flip(first: false), atMillis: 2100)).isEmpty)
    }

    @Test("A switch fades its new case in, and the old one goes at once", arguments: [1, 2])
    func switchFades(to which: Int) {
        let frames = Frames()
        let drawn = which == 1 ? "ZZZ" : "YY"
        _ = frames.draw(Cases(which: 0), atMillis: 0)
        #expect(frames.draw(Cases(which: which), atMillis: 1000, changed: true).first == drawn, "the old gone")
        #expect(fades(frames.buffer(Cases(which: which), atMillis: 1750)) == [0.75], "the new fading in")
        #expect(frames.draw(Cases(which: which), atMillis: 2100).first == drawn)
    }

    @Test("Without an animation a branch flips at once")
    func unanimatedFlipIsInstant() {
        let frames = Frames()
        _ = frames.draw(Flip(first: true), atMillis: 0)
        let flipped = frames.buffer(Flip(first: false), atMillis: 1000)
        #expect(flipped.withLayersDrawn().lines.map(\.stripped).first == "YY  ")
        #expect(fades(flipped).isEmpty)
    }

    /// Drawn whole, the new branch fades in where the layout puts it, and
    /// nothing of the old is drawn past it: SwiftUI's two overlap at the
    /// conditional's origin while the old fades out (T8).
    @Test("A body that is an if/else fades its new branch in, and the old one goes at once")
    func wholeBodyFlipFades() {
        let frames = Frames()
        _ = frames.draw(WholeBody(first: true), atMillis: 0)
        _ = frames.buffer(WholeBody(first: false), atMillis: 1000, changed: true)
        let half = frames.buffer(WholeBody(first: false), atMillis: 1750)
        #expect(half.lines.map(\.stripped) == ["YY"], "laid out as the new branch")
        #expect(half.withLayersDrawn().lines.map(\.stripped) == ["YY"], "nothing of the old drawn past it")
        #expect(fades(half) == [0.75], "\(fades(half))")
        let end = frames.buffer(WholeBody(first: false), atMillis: 2100)
        #expect(end.withLayersDrawn().lines.map(\.stripped) == ["YY"])
        #expect(fades(end).isEmpty)
    }

    // MARK: - Rows

    /// The row fades in where it lands while the rows below glide down out
    /// of its way (T3).
    @Test("A row inserted fades in while the rows below glide")
    func rowInsertedFades() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 3]), atMillis: 0)
        let start = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 1000, changed: true)
        #expect(start.prefix(3) == ["1111", "3333", "----"], "nothing has moved yet: \(start)")
        let late = frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1600)
        #expect(late.withLayersDrawn().lines.map(\.stripped).prefix(4) == ["1111", "2222", "3333", "----"])
        #expect(fades(late) == [0.6], "fading in: \(fades(late))")
        #expect(fades(frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 2100)).isEmpty)
    }

    /// The row is gone on the frame of the change, and the rows below glide
    /// up into its room: SwiftUI's fades out where it was, beneath them.
    @Test("A row removed goes at once while the rows below glide up")
    func rowRemovedGoes() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 0)
        let start = frames.draw(Rows(ids: [1, 3]), atMillis: 1000, changed: true)
        #expect(start.prefix(3) == ["1111", "", "3333"], "gone, and the row below not yet moved: \(start)")
        #expect(fades(frames.buffer(Rows(ids: [1, 3]), atMillis: 1300)).isEmpty, "nothing fading")
        let late = frames.draw(Rows(ids: [1, 3]), atMillis: 1700)
        #expect(late.prefix(2) == ["1111", "3333"], "the row below has glided up: \(late)")
        #expect(frames.draw(Rows(ids: [1, 3]), atMillis: 2100) == ["1111", "3333", "----"])
    }

    /// Gone at once, it has no presence left to turn round from: it fades in
    /// again from nothing, as a row inserted does.
    @Test("A row that comes back after it went fades in from nothing")
    func returningRowFadesIn() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 0)
        _ = frames.draw(Rows(ids: [1, 3]), atMillis: 1000, changed: true)
        let back = frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1300, changed: true)
        #expect(fades(back) == [0], "from nothing: \(fades(back))")
        #expect(fades(frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1600)) == [0.3])
        #expect(fades(frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 2400)).isEmpty)
    }

    @Test("Without an animation rows come and go at once")
    func unanimatedRowsAreInstant() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 3]), atMillis: 0)
        let inserted = frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1000)
        #expect(fades(inserted).isEmpty)
        #expect(frames.draw(Rows(ids: [1, 3]), atMillis: 2000) == ["1111", "3333", "----"])
    }

    @Test("A stack seen for the first time is not an arrival")
    func firstSightIsNotAnArrival() {
        let frames = Frames()
        #expect(fades(frames.buffer(Rows(ids: [1, 2]), atMillis: 0, changed: true)).isEmpty)
        #expect(fades(frames.buffer(Flip(first: true), atMillis: 0, changed: true)).isEmpty)
    }

    /// A fade is not motion, which reduce motion holds still (owner decision
    /// A-D3M-1): the rows below jump, and the row still fades in.
    @Test("Under reduce motion a row still fades in, and the rows below jump")
    func reduceMotionStillFades() {
        let frames = Frames(reduceMotion: true)
        _ = frames.draw(Rows(ids: [1, 3]), atMillis: 0)
        _ = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 1000, changed: true)
        let late = frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1600)
        #expect(late.withLayersDrawn().lines.map(\.stripped).prefix(3) == ["1111", "2222", "3333"])
        #expect(fades(late) == [0.6])
    }

    /// A row with a transition of its own plays it where the stack saw it
    /// go, as an `if`'s view does where its `nil` holds a slot.
    @Test("A row with a transition of its own plays it as it leaves")
    func rowPlaysItsOwnTransition() {
        let frames = Frames()
        _ = frames.draw(SlidingRows(ids: [1, 2]), atMillis: 0)
        #expect(frames.draw(SlidingRows(ids: [1]), atMillis: 1000, changed: true) == ["----", "1111", "2222"])
        #expect(frames.draw(SlidingRows(ids: [1]), atMillis: 1500) == ["----", "1111", "  22"], "sliding out")
        #expect(frames.draw(SlidingRows(ids: [1]), atMillis: 2100) == ["----", "1111"])
    }

    /// SwiftUI runs a transition's own animation with no `withAnimation`
    /// (`Tools/SwiftUIProbes/Transitions/tr1.out` T6), and so does an `if`
    /// whose `nil` plays the removal. A row, a branch taken apart by its stack
    /// and one drawn whole went at once: the stack skipped what came and went
    /// on a change nothing animated, and the removal asked for the change's
    /// animation, not the transition's.
    @Test("A row with a transition of its own animation plays its removal with no animated change")
    func timedRowLeavesUnanimated() {
        let frames = Frames()
        // A transition's own animation plays its arrival too: arrived.
        _ = frames.draw(TimedRows(ids: [1, 2]), atMillis: 0)
        #expect(frames.draw(TimedRows(ids: [1, 2]), atMillis: 1100) == ["----", "1111", "2222"])
        #expect(frames.draw(TimedRows(ids: [1]), atMillis: 2000) == ["----", "1111", "2222"])
        #expect(frames.draw(TimedRows(ids: [1]), atMillis: 2500) == ["----", "1111", "  22"], "sliding out")
        #expect(frames.draw(TimedRows(ids: [1]), atMillis: 3100) == ["----", "1111"])
    }

    @Test(
        "A branch with a transition of its own animation plays its removal with no animated change",
        arguments: [TimedBranchShape.stacked, .whole, .ifAlone])
    func timedBranchLeavesUnanimated(shape: TimedBranchShape) {
        switch shape {
        case .stacked: Self.leavesUnanimated(remaining: ["----", "YY"]) { TimedFlip(first: $0) }
        case .whole: Self.leavesUnanimated(remaining: ["----", "YY"]) { TimedWholeFlip(first: $0) }
        case .ifAlone: Self.leavesUnanimated(remaining: ["----"]) { TimedIf(first: $0) }
        }
    }

    /// Whether the view `scene` makes slides its first branch out over the
    /// second of its own animation when it is left with no animated change,
    /// and leaves `remaining` drawn.
    private static func leavesUnanimated<V: View>(remaining: [String], _ scene: (Bool) -> V) {
        let frames = Frames()
        _ = frames.draw(scene(true), atMillis: 0)
        #expect(frames.draw(scene(true), atMillis: 1100) == ["----", "XXXX"], "arrived")
        _ = frames.draw(scene(false), atMillis: 2000)
        let half = frames.draw(scene(false), atMillis: 2500)
        #expect(half.count > 1 && half[1].hasSuffix("XX") && !half[1].hasPrefix("XX"), "sliding out: \(half)")
        #expect(frames.draw(scene(false), atMillis: 3100) == remaining)
    }

    /// A view an `if` brings back is a new view, as SwiftUI's is: it fades in
    /// whole, and nothing inside it fades or glides from what it showed
    /// before it went. The records a conditional, a stack and an `if` keep
    /// of their last frame outlast a view that goes, and one that came back
    /// played what had changed while it was gone — the branch it no longer
    /// takes, the row it no longer has, the view its `if` no longer holds —
    /// as ghosts fading over it.
    @Test("A view that comes back after a pass unseen shows nothing of what it showed before it went")
    func returningViewHasNoGhosts() {
        let frames = Frames()
        _ = frames.draw(Hidden(showing: true, inner: true), atMillis: 0)
        _ = frames.draw(Hidden(showing: false, inner: true), atMillis: 1000)
        _ = frames.draw(Hidden(showing: false, inner: false), atMillis: 2000)
        _ = frames.draw(Hidden(showing: true, inner: false), atMillis: 3000, changed: true)
        let back = frames.draw(Hidden(showing: true, inner: false), atMillis: 3250)
        #expect(back == ["----", "YY", "1111", "----", "<>"], "\(back)")
        let fading = fades(frames.buffer(Hidden(showing: true, inner: false), atMillis: 3500))
        #expect(fading == [0.5], "the view fades in whole, and nothing in it: \(fading)")
    }

    /// An `if` holding several views keeps no one slot for its `nil` to
    /// play in, and no picture of them: the stack sees each of them go, and
    /// lets it go, as it does a row.
    @Test("An if holding several views lets each go at once")
    func severalGoAtOnce() {
        let frames = Frames()
        _ = frames.draw(Several(showing: true), atMillis: 0)
        #expect(frames.draw(Several(showing: false), atMillis: 1000, changed: true) == ["----"])
        #expect(fades(frames.buffer(Several(showing: false), atMillis: 1300)).isEmpty)
    }

    /// What an `if` in a stack hands the stack is the stack's child, as a
    /// row is: it fades in where it lands, and goes at once. TRANSITIONS2's
    /// stack faded it out from the picture it kept of every child.
    @Test("An if in a stack fades in what it hands the stack, and lets it go at once",
        arguments: HandedOverShape.allCases)
    func handedOverGoesAtOnce(shape: HandedOverShape) {
        let frames = Frames()
        _ = frames.draw(HandedOverInStack(showing: false, shape: shape), atMillis: 0)
        _ = frames.draw(HandedOverInStack(showing: true, shape: shape), atMillis: 1000, changed: true)
        let arriving = fades(frames.buffer(HandedOverInStack(showing: true, shape: shape), atMillis: 1500))
        #expect(arriving == [0.5], "fading in: \(arriving)")
        _ = frames.draw(HandedOverInStack(showing: true, shape: shape), atMillis: 2100)
        let removed = frames.draw(HandedOverInStack(showing: false, shape: shape), atMillis: 3000, changed: true)
        #expect(removed == ["----"], "gone on the frame of the change: \(removed)")
        #expect(fades(frames.buffer(HandedOverInStack(showing: false, shape: shape), atMillis: 3500)).isEmpty)
    }

    /// Rendered directly, the `if` holds whatever it holds, and keeps its
    /// picture: it fades it out where it was.
    @Test("An if rendered directly fades out whatever it holds", arguments: HandedOverShape.allCases)
    func heldDirectlyFadesOut(shape: HandedOverShape) {
        let frames = Frames()
        _ = frames.draw(HandedOverDirectly(showing: true, shape: shape), atMillis: 0)
        _ = frames.draw(HandedOverDirectly(showing: false, shape: shape), atMillis: 1000, changed: true)
        let leaving = fades(frames.buffer(HandedOverDirectly(showing: false, shape: shape), atMillis: 1500))
        #expect(leaving == [0.5], "fading out: \(leaving)")
    }
}
