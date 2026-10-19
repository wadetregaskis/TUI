//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BranchAndRowFadeTests.swift
//
//  The default transition for what is not an `if`: the branch an `if`/`else`
//  flips to, a `switch`'s case, a `ForEach`'s row. Each fades in where it
//  lands and out where it was, beneath the views around it, while they
//  glide, as SwiftUI's do with no `.transition` written (measured,
//  `Tools/SwiftUIProbes/Transitions/tr1.out` T1–T3 and T8).
//
//  A fade is an opacity claim on the cells, and where two pictures overlap
//  the compositor resolves the top one's claim against the cells beneath:
//  its glyph shows from half-way, the one beneath until then. So these read
//  the glyphs drawn, and the claims left where nothing is beneath.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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
@Suite("A branch, a case and a row fade in and out by default")
struct BranchAndRowFadeTests {

    // MARK: - A branch flip

    /// The leaving branch fades out where it was, beneath, and the new one in
    /// over it: the old glyphs show until half-way, the new from there, and
    /// what of the old the new does not cover goes on fading.
    @Test("An if/else whose branch flips fades the old branch out and the new one in")
    func branchFlipFades() {
        let frames = Frames()
        _ = frames.draw(Flip(first: true), atMillis: 0)
        #expect(frames.draw(Flip(first: false), atMillis: 1000, changed: true) == ["XXXX", "----"], "from the old")
        #expect(frames.draw(Flip(first: false), atMillis: 1250) == ["XXXX", "----"], "the old still shows")
        let late = frames.buffer(Flip(first: false), atMillis: 1750)
        #expect(late.withLayersDrawn().lines.map(\.stripped).first == "YYXX", "the new over what is left")
        #expect(fades(late).contains(0.25), "what is left of the old fading: \(fades(late))")
        let end = frames.buffer(Flip(first: false), atMillis: 2100)
        #expect(end.withLayersDrawn().lines.map(\.stripped).first == "YY  ")
        #expect(fades(end).isEmpty)
    }

    @Test("A switch fades its old case out and its new one in", arguments: [1, 2])
    func switchFades(to which: Int) {
        let frames = Frames()
        _ = frames.draw(Cases(which: 0), atMillis: 0)
        #expect(frames.draw(Cases(which: which), atMillis: 1000, changed: true).first == "XXXX")
        let late = frames.draw(Cases(which: which), atMillis: 1750)
        #expect(late.first == (which == 1 ? "ZZZX" : "YYXX"), "\(late)")
        #expect(frames.draw(Cases(which: which), atMillis: 2100).first == (which == 1 ? "ZZZ" : "YY"))
    }

    @Test("Without an animation a branch flips at once")
    func unanimatedFlipIsInstant() {
        let frames = Frames()
        _ = frames.draw(Flip(first: true), atMillis: 0)
        let flipped = frames.buffer(Flip(first: false), atMillis: 1000)
        #expect(flipped.withLayersDrawn().lines.map(\.stripped).first == "YY  ")
        #expect(fades(flipped).isEmpty)
    }

    /// Drawn whole, the two branches overlap at the conditional's origin, as
    /// SwiftUI's do (T8): the new one where the layout puts it, the old one
    /// drawn past it while it fades.
    @Test("A body that is an if/else fades its old branch out over its new one")
    func wholeBodyFlipFades() {
        let frames = Frames()
        _ = frames.draw(WholeBody(first: true), atMillis: 0)
        _ = frames.buffer(WholeBody(first: false), atMillis: 1000, changed: true)
        let half = frames.buffer(WholeBody(first: false), atMillis: 1750)
        #expect(half.lines.map(\.stripped) == ["YY"], "laid out as the new branch")
        #expect(half.withLayersDrawn().lines.map(\.stripped) == ["XXXX"], "the old drawn past it")
        #expect(fades(half).sorted() == [0.25, 0.75], "\(fades(half))")
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

    /// The row fades out where it was, beneath the rows gliding up over it.
    @Test("A row removed fades out where it was while the rows below glide up")
    func rowRemovedFades() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 0)
        #expect(frames.draw(Rows(ids: [1, 3]), atMillis: 1000, changed: true).prefix(3) == ["1111", "2222", "3333"])
        let early = frames.buffer(Rows(ids: [1, 3]), atMillis: 1300)
        #expect(early.withLayersDrawn().lines.map(\.stripped).prefix(3) == ["1111", "2222", "3333"])
        #expect(fades(early) == [0.7], "fading out: \(fades(early))")
        let late = frames.draw(Rows(ids: [1, 3]), atMillis: 1700)
        #expect(late.prefix(2) == ["1111", "3333"], "the row below has glided over it: \(late)")
        #expect(frames.draw(Rows(ids: [1, 3]), atMillis: 2100) == ["1111", "3333", "----"])
    }

    /// Its presence is one value, so the arrival starts where the removal
    /// had got to rather than from nothing.
    @Test("A row that comes back while it leaves turns round from where it is")
    func returningRowTurnsRound() {
        let frames = Frames()
        _ = frames.draw(Rows(ids: [1, 2, 3]), atMillis: 0)
        _ = frames.draw(Rows(ids: [1, 3]), atMillis: 1000, changed: true)
        let back = frames.buffer(Rows(ids: [1, 2, 3]), atMillis: 1300, changed: true)
        #expect(fades(back) == [0.7], "no jump: \(fades(back))")
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

    /// An `if` holding several views keeps no one slot for its `nil` to
    /// play in; the stack sees each of them go.
    @Test("An if holding several views fades each out where it was")
    func severalFadeOut() {
        let frames = Frames()
        _ = frames.draw(Several(showing: true), atMillis: 0)
        _ = frames.draw(Several(showing: false), atMillis: 1000, changed: true)
        let early = frames.buffer(Several(showing: false), atMillis: 1300)
        #expect(early.withLayersDrawn().lines.map(\.stripped) == ["----", "AAAA", "BBBB"])
        #expect(fades(early) == [0.7, 0.7])
        #expect(frames.draw(Several(showing: false), atMillis: 2100) == ["----"])
    }
}
