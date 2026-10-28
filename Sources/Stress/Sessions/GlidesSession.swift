//  🖥️ TUI — A Terminal UI framework for Swift
//  GlidesSession.swift
//
//  Views coming and going under `withAnimation`, in each container that glides
//  its children (decisions FB16): the frames a glide or a removal plays on are
//  functions of the clock, and no other session draws one — every other
//  session's changes are unanimated, so its containers only ever draw settled.
//  Played with its cache-cleared twin, and under the memo verifiers, this is
//  what checks that no memo serves a frame of a glide inside a memoized card,
//  or of a removal playing inside a memoized note, from a buffer it kept — with
//  the terminal resized under a glide whenever the runner resizes it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUI

// MARK: - The model

/// What comes and goes on the page, and a clock.
@Observable
@MainActor
final class GlidesModel {
    /// Two rows in a column, above a row that glides.
    var detail = false
    /// A badge in a row, before a label that glides.
    var badge = true
    /// A wide layer under a narrow one, which is re-centred as it comes and goes.
    var wide = false
    /// A subview of a `Layout`, before one the layout moves.
    var extra = false
    /// The detail of a memoized card, swapped for a line: a branch, not a
    /// transition.
    var cardOpen = false
    /// The detail of a memoized note, which comes and goes with a transition.
    var noteOpen = true
    /// A banner that is the whole content of a stack of its own, in a stack
    /// with gaps.
    var banner = true
    /// A detail that folds away under a transition of the app's own, whose
    /// body changes the view's height between its phases.
    var fold = false
    /// Whether the middle row of a loop is there: a row the change puts in
    /// fades in, with no transition written, and one it takes out goes at
    /// once.
    var row = true
    /// Moved every step, unanimated: a frame is drawn on every step, and each
    /// card is served on every one its value has not changed on.
    var tick = 0
    /// How many animated changes have been made.
    var changes = 0
}

// MARK: - The page

/// One of each container that glides, each with something that comes and goes.
struct GlidesPage: View {
    let model: GlidesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "changes \(model.changes)")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "column")
                if model.detail {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "detail one")
                        Text(verbatim: "detail two")
                    }
                    .transition(.opacity)
                }
                Text(verbatim: "column end")
            }
            HStack(spacing: 1) {
                Text(verbatim: "row")
                if model.badge { Text(verbatim: "[badge]").transition(.move(edge: .leading)) }
                Text(verbatim: "row end")
            }
            ZStack {
                if model.wide { Text(verbatim: "==============").transition(.opacity) }
                Text(verbatim: "layer")
            }
            HStackLayout(spacing: 1) {
                Text(verbatim: "laid")
                if model.extra { Text(verbatim: "extra").transition(.scale) }
                Text(verbatim: "out")
            }
            GlidesCard(open: model.cardOpen).equatable()
            GlidesNote(open: model.noteOpen).equatable()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "above")
                VStack(alignment: .leading, spacing: 0) {
                    if model.banner {
                        Text(verbatim: "BANNER").padding(.horizontal, 1).border(.palette.accent)
                            .transition(.move(edge: .trailing))
                    }
                }
                Text(verbatim: "below")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "folds")
                if model.fold {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "fold one")
                        Text(verbatim: "fold two")
                    }
                    .transition(GlidesFold())
                }
                ForEach(model.row ? ["row a", "row b", "row c"] : ["row a", "row c"], id: \.self) { row in
                    Text(verbatim: row)
                }
                Text(verbatim: "folds end")
            }
            GlidesClock(model: model)
        }
    }
}

/// A transition of the app's own that folds its two rows away to none: its
/// body is drawn by scrubbing between its phases, inside the size it has at
/// rest, while the rows below glide with the change (decisions B52,
/// A-TRANSITIONS2-1).
private struct GlidesFold: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.frame(height: phase.isIdentity ? 2 : 0, alignment: .top)
    }
}

/// The clock, read in a body of its own: a write to it redraws this alone.
/// Read in the page's body, every step's tick cleared what the cache kept of
/// everything on the page, and the card was never served.
private struct GlidesClock: View {
    let model: GlidesModel

    var body: some View {
        Text(verbatim: "tick \(model.tick)")
    }
}

/// A card memoized by its value, whose detail is swapped for a line inside
/// it: the row below glides in a subtree a memo serves on every frame the
/// card's value has not changed on. A branch swap, not a `.transition` — a
/// view with one is drawn afresh on every frame anyway, and would hide a memo
/// that kept a frame of the glide; the branch taken fades in by default only
/// while it comes.
private struct GlidesCard: View, @MainActor Equatable {
    let open: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.open == rhs.open }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "card")
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "card detail")
                    Text(verbatim: "card more")
                }
            } else {
                Text(verbatim: "-")
            }
            Text(verbatim: "card end")
        }
        .border(.palette.border)
    }
}

/// A note memoized by its value, whose detail comes and goes with a
/// transition: a removal playing, and the row below gliding over it, in a
/// subtree a memo serves once it has played.
private struct GlidesNote: View, @MainActor Equatable {
    let open: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.open == rhs.open }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "note")
            if open {
                Text(verbatim: "note detail").transition(.move(edge: .leading))
            }
            Text(verbatim: "note end")
        }
    }
}

// MARK: - The script

/// Someone opening and closing the parts of a page, each change animated, the
/// next often made before the last has landed.
@MainActor
final class GlidesSession: StressSession {
    /// The parts that come and go, each with the text that shows it.
    enum Part: String, CaseIterable {
        case detail, badge, wide, extra, card, note, banner, fold, row

        @MainActor var keyPath: ReferenceWritableKeyPath<GlidesModel, Bool> {
            switch self {
            case .detail: \.detail
            case .badge: \.badge
            case .wide: \.wide
            case .extra: \.extra
            case .card: \.cardOpen
            case .note: \.noteOpen
            case .banner: \.banner
            case .fold: \.fold
            case .row: \.row
            }
        }

        var marker: String {
            switch self {
            case .detail: "detail one"
            case .badge: "[badge]"
            case .wide: "=layer="
            case .extra: "extra"
            case .card: "card detail"
            case .note: "note detail"
            case .banner: "BANNER"
            case .fold: "fold one"
            case .row: "row b"
            }
        }
    }

    /// The animations a change is made under: curves that add when a change
    /// interrupts one in flight, and springs that merge (decisions O3).
    static let animations: [Animation] = [
        .linear(duration: 0.3), .easeInOut(duration: 0.25), .spring(duration: 0.4), .spring(duration: 0.3, bounce: 0.3),
    ]

    /// Steps after a change by which everything it moved has landed, however
    /// it was animated: a second and a quarter at sixty frames a second.
    static let settledAfter = 75

    private let model = GlidesModel()
    private var random: SessionRandom
    /// The step each part last changed on.
    private var changedAt: [Part: Int] = [:]
    /// The banner's last change while it plays: the rows from `above` to
    /// `below` it started from and is going to, and whether a frame has drawn
    /// them anywhere else — part-way.
    private var bannerMove: (step: Int, from: Int, to: Int, seenPartWay: Bool, framesSeen: Int)?
    /// The screen's height at the last check, and the step it last changed on.
    private var screenHeight: Int?
    private var resizedAt = -GlidesSession.settledAfter
    /// The rows from `above` to `below` on the last frame that drew both.
    private var bannerRows = 6

    init(config: StressConfig) {
        random = SessionRandom(seed: config.seed ^ 0x611D)
    }

    var page: GlidesPage { GlidesPage(model: model) }

    /// One step in seven toggles a part, inside a `withAnimation`; the rest
    /// only move the clock, so a change plays out over the frames after it,
    /// and a part changed again before it has landed is interrupted.
    ///
    /// The toggle is written before the clock. An observation fires once, on
    /// the first write after the body that armed it drew, and that write's
    /// transaction is the one the next frame is drawn under: with the clock
    /// read in the page's body and written first, no change was ever
    /// animated. It is read in a body of its own now, and written last all
    /// the same.
    func step(_ index: Int) -> SessionStep {
        defer { model.tick += 1 }
        guard random.below(7) == 0 else { return SessionStep(action: "tick") }
        let part = Part.allCases[random.below(Part.allCases.count)]
        let animation = Self.animations[random.below(Self.animations.count)]
        withAnimation(animation) { model[keyPath: part.keyPath].toggle() }
        model.changes += 1
        changedAt[part] = index
        if part == .banner {
            bannerMove = (index, bannerRows, model.banner ? 6 : 2, false, 0)
        }
        return SessionStep(action: part.rawValue)
    }

    /// The header counts the changes; the banner's last change was drawn
    /// part-way; and where the whole page is on the screen, every part that
    /// has had time to land is drawn or not as the model says, and the rows a
    /// column and the banner's stack moved stand where their layout puts them.
    func check(_ screen: [String], after index: Int) -> String? {
        let header = "changes \(model.changes)"
        guard screen.contains(where: { $0.contains(header) }) else { return "the page does not say \(header)" }
        if let above = screen.firstIndex(where: { $0.contains("above") }),
            let below = screen.firstIndex(where: { $0.contains("below") }),
            let problem = noteBanner(rows: below - above, after: index)
        {
            return problem
        }
        // A resize is a change of layout too: a column it squeezes moves the
        // rows of its stacks (A-LAYOUT-1), and one with a glide in flight
        // carries them there by that glide, so nothing counts as landed until
        // the frames after a resize have played. The runner resizes; the
        // screen's height is how the page sees it.
        if screen.count != screenHeight {
            if screenHeight != nil { resizedAt = index }
            screenHeight = screen.count
        }
        let landed = Part.allCases.filter {
            index - max(changedAt[$0] ?? -Self.settledAfter, resizedAt) >= Self.settledAfter
        }
        // The clock is the page's last row, but drawn is not the same as fitting:
        // a column too short for the page squeezes its stacks (A-LAYOUT-1), so the
        // banner's can lose its rows while the clock still shows.
        guard screen.contains(where: { $0.contains("tick \(model.tick)") }),
            screen.count >= rowsNeeded(landed: landed)
        else { return nil }
        for part in landed {
            let isOn = model[keyPath: part.keyPath]
            if screen.contains(where: { $0.contains(part.marker) }) != isOn {
                return "\(part.rawValue) is \(isOn ? "on" : "off") but \(part.marker) is \(isOn ? "not " : "")drawn"
            }
        }
        func row(_ text: String) -> Int? { screen.firstIndex { $0.contains(text) } }
        if landed.contains(.detail), let top = row("column"), let end = row("column end"),
            end != top + (model.detail ? 3 : 1)
        {
            return "column end is \(end - top) rows below column, with the detail \(model.detail ? "open" : "closed")"
        }
        if landed.contains(.fold), landed.contains(.row), let top = row("folds"), let end = row("folds end"),
            end != top + 1 + (model.fold ? 2 : 0) + (model.row ? 3 : 2)
        {
            return "folds end is \(end - top) rows below folds, with the fold \(model.fold ? "open" : "closed")"
                + " and the middle row \(model.row ? "in" : "out")"
        }
        if landed.contains(.banner), let above = row("above"), let below = row("below"),
            below != above + (model.banner ? 6 : 2)
        {
            return "below is \(below - above) rows below above, with the banner \(model.banner ? "up" : "down")"
        }
        return nil
    }

    /// The rows the page takes, a part still playing counted at its taller end.
    private func rowsNeeded(landed: [Part]) -> Int {
        func on(_ part: Part) -> Bool { !landed.contains(part) || model[keyPath: part.keyPath] }
        let column = 2 + (on(.detail) ? 2 : 0)
        let card = 2 + (on(.card) ? 4 : 3)
        let note = 2 + (on(.note) ? 1 : 0)
        let banner = on(.banner) ? 7 : 3
        let folds = 2 + (on(.fold) ? 2 : 0) + (on(.row) ? 3 : 2)
        return 1 + column + 3 + card + note + banner + folds + 1
    }

    /// Notes the rows a frame drew the banner's stack across, and says what is
    /// wrong when the banner's last change has landed without a frame drawing
    /// it part-way: a change that was not animated, on a page that would then
    /// draw no glide at all — which this session did, verified clean, before
    /// it wrote its clock after its changes (see ``step(_:)``).
    private func noteBanner(rows: Int, after index: Int) -> String? {
        defer { bannerRows = rows }
        guard var move = bannerMove else { return nil }
        move.framesSeen += 1
        if rows != move.from, rows != move.to { move.seenPartWay = true }
        bannerMove = move
        guard index - move.step >= Self.settledAfter else { return nil }
        bannerMove = nil
        guard !move.seenPartWay, move.from != move.to, move.framesSeen > 2 else { return nil }
        return "the banner's change at step \(move.step) was never drawn part-way: nothing glided"
    }

    static let descriptor = SessionDescriptor(
        id: "glides",
        summary: "parts of a page coming and going under withAnimation, the next change often before the last lands",
        exercises:
            "siblings gliding in an eager VStack and HStack, a ZStack re-centring a layer, a Layout's subviews, "
            + "a glide inside an .equatable() card and a removal inside an .equatable() note, each served "
            + "between changes, a view leaving a stack "
            + "of its own in a spaced stack, a transition of the app's own folding a detail away, a loop's "
            + "row fading in and out; linear, eased and spring animations interrupted mid-flight",
        make: { config, width, height, cold in
            DrivenSession(GlidesSession(config: config), width: width, height: height, cold: cold)
        })
}
