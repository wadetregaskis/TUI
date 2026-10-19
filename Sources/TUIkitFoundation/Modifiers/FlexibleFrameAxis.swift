//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FlexibleFrameAxis.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// One axis of a flexible frame — its minimum, ideal and maximum — and
/// SwiftUI's rule for what the frame offers its content along it and how
/// large the frame is around what comes back.
///
/// The rule, measured (`Tools/SwiftUIProbes/Flexible frames/frame.out`) and as
/// SwiftUI documents it: the frame offers its content its own offer, or its
/// ideal when it was offered nothing, held to the maximum. Its size is then
/// the content's, raised to the minimum where the content is smaller than the
/// offer and grown to the offer, up to the maximum, where the content is
/// larger than it — so a frame with both fills its offer between the two, one
/// with a maximum alone fills it up to that maximum (`.frame(maxWidth: 30)`
/// over a five-cell `Text` is 30 wide offered 80), and an ideal is read only
/// when nothing was offered: offered 80, `.frame(idealWidth: 10)` leaves a
/// long `Text` its 37 cells.
///
/// Offered nothing, a frame with an ideal is exactly its ideal, as SwiftUI's
/// is (``extentOfferedNothing(content:)``): `.frame(idealWidth: 10)` around a
/// five-cell `Text` under `.fixedSize()` is ten wide, its text placed in it by
/// the frame's alignment. Along the width, "offered nothing" is the ideal-width
/// ask and the drawing under `.fixedSize()` that follows it
/// (``EnvironmentValues/fixedSizeWidth``), so the frame draws the width it
/// measured.
///
/// Two differences, both because a terminal draws inside what it is given.
/// The content is not offered more than the frame was, where SwiftUI raises
/// the offer to the minimum (the frame would only be cut back to the offer).
/// And down the column, a frame with an ideal height and no maximum, offered
/// nothing, is its content's height, where SwiftUI's is the ideal: a stack asks
/// every child its natural height by offering it none, so that ask is not
/// SwiftUI's unspecified proposal, and answering the ideal there would lay
/// such a frame out at its ideal in every column (deviations L16).
struct FlexibleFrameAxis {
    let minimum: Int?
    let ideal: Int?
    let maximum: FrameDimension?

    /// Contradictory constraints are put in order, as SwiftUI's are (it logs
    /// "Contradictory frame constraints specified"): an ideal below the
    /// minimum is the minimum, and a maximum below either is the larger of
    /// them — `.frame(idealWidth: 40, maxWidth: 30)` fills to 40, measured.
    init(minimum: Int?, ideal: Int?, maximum: FrameDimension?) {
        let ideal = ideal.map { Swift.max($0, minimum ?? $0) }
        self.minimum = minimum
        self.ideal = ideal
        if case .fixed(let value)? = maximum {
            self.maximum = .fixed(Swift.max(value, ideal ?? minimum ?? value, minimum ?? value))
        } else {
            self.maximum = maximum
        }
    }

    /// Whether the frame fills whatever it is offered (`.infinity`).
    var fills: Bool {
        if case .infinity? = maximum { return true }
        return false
    }

    /// The finite maximum, if the frame has one.
    var finiteMaximum: Int? {
        if case .fixed(let value)? = maximum { return value }
        return nil
    }

    /// The extent the content is laid out in when the frame is offered
    /// `offer`: that offer, or — `unspecified`, the frame itself offered
    /// nothing and `offer` only the budget a measure runs in — its ideal,
    /// held to the maximum and never beyond the offer. Offered nothing and
    /// with no ideal, the frame proposes nothing in turn
    /// (``contentProposal(_:unspecified:)``), and the content's own ideal is
    /// not held to the maximum — the frame is (`.frame(maxWidth: 30)` over a
    /// 37-cell line is 30 wide, the line wrapped in it). Never negative: an
    /// app's own arithmetic — `.frame(width: available - labelWidth)` —
    /// arrives here unexamined, and a leaf that builds a run from its offer
    /// (`Divider`) has no defence.
    func contentBudget(_ offer: Int, unspecified: Bool) -> Int {
        if unspecified, ideal == nil { return Swift.max(0, offer) }
        var target = (unspecified ? ideal.map { Swift.min($0, offer) } : nil) ?? offer
        if let finiteMaximum { target = Swift.min(target, finiteMaximum) }
        return Swift.max(0, target)
    }

    /// What the content is proposed: its budget, or nothing where the frame
    /// was offered nothing and has no ideal to offer instead — SwiftUI's
    /// frame passes an unspecified proposal on.
    func contentProposal(_ offer: Int, unspecified: Bool) -> Int? {
        unspecified && ideal == nil ? nil : contentBudget(offer, unspecified: unspecified)
    }

    /// The frame's extent around content `content` long, offered `offer` —
    /// `nil` when it was offered nothing — before the cut to what it was
    /// offered. Never negative, for the reason the content's budget is not: a
    /// maximum of `available - labelWidth` can be below zero.
    func extent(content: Int, offer: Int?) -> Int {
        let proposal = offer ?? ideal
        var result = content
        if let minimum {
            result = Swift.max(minimum, proposal.map { Swift.min(result, $0) } ?? result)
        }
        switch maximum {
        case .fixed(let value): result = Swift.min(value, proposal.map { Swift.max(result, $0) } ?? result)
        case .infinity: result = proposal.map { Swift.max(result, $0) } ?? result
        case nil: break
        }
        return Swift.max(0, result)
    }

    /// The frame's extent around content `content` long when it is offered
    /// nothing at all: its ideal, where it has one — held to its minimum and
    /// maximum already, as the initialiser orders them — and otherwise
    /// ``extent(content:offer:)`` with no offer. SwiftUI's rule, measured
    /// (`Tools/SwiftUIProbes/Flexible frames/frame.out`, the `[ideal]` rows:
    /// `short ideal 10` is 10, `short min 10 ideal 20` 20).
    func extentOfferedNothing(content: Int) -> Int {
        guard let ideal else { return extent(content: content, offer: nil) }
        return Swift.max(0, ideal)
    }

    /// Whether offering the frame more would make it larger, given the
    /// extent it reported and the extent it wanted before being cut to its
    /// offer: always where it fills, wherever the cut engaged, and otherwise
    /// up to a finite maximum, or as far as its content grows when it has
    /// none.
    func isFlexible(reported: Int, wanted: Int, contentFlexible: Bool) -> Bool {
        if fills || reported < wanted { return true }
        if let finiteMaximum { return wanted < finiteMaximum }
        return contentFlexible
    }
}
