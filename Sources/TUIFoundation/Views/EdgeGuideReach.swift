//  🖥️ TUI — A Terminal UI framework for Swift
//  EdgeGuideReach.swift
//
//  Whether an edge or centre guide can leave a view, asked of its type: what
//  lets a container skip a child whose guides are all kept inside a stack of
//  several views (decisions A-GUIDE-2).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// Whether a view of `type` may report an edge or centre guide (`.leading`,
/// `.center`, `.trailing`, `.top`, `.bottom`) out of itself, from its type
/// alone — whether ``explicitGuide(of:_:in:context:)`` can answer one.
///
/// ``View/_providesAlignmentGuide`` says whether a view may report any guide,
/// and since B19 a view of the app's own answers with its body. A stack of
/// several views reports no edge or centre guide (A-GUIDE-2), so a guide set
/// on a view inside one can only leave as a baseline or a custom guide — but
/// the witness cannot tell the kinds apart, and said "may" for every row type
/// holding a guide anywhere. A lazy stack, aligning its rows on an edge or the
/// centre, then gave up its window and built and measured every row on every
/// walk (`struct Row: View { var body: some View { HStack(alignment: .top) {
/// mark.alignmentGuide(.top) { _ in 0 }; Text(…) } } }`: 18,011 body
/// evaluations for 3,000 rows, where 71 draw ten), and an eager stack
/// evaluated such a view's body to ask it for a guide it could not have
/// (found in review).
///
/// `true` wherever the type does not say otherwise — `false` skips a question
/// whose answer was `nil` anyway, so a `true` too many costs only that
/// question. Kept per type (``BodyWitnessMemo``), as the witness is.
@MainActor
package func mayReportEdgeOrCentreGuide<V: View>(_ type: V.Type) -> Bool {
    guard V._providesAlignmentGuide else { return false }
    return BodyWitnessMemo.answer(in: BodyWitnessMemo.edgeOrCentreGuide, for: type) { edgeGuideReach(of: type) }
}

/// ``mayReportEdgeOrCentreGuide(_:)`` worked out, past the witness — as
/// ``explicitGuide(of:_:in:context:)`` asks: a type that says so itself, any
/// other that answers the query itself as "may", a wrapper that keeps its
/// content's geometry by its content, a view of the app's own by its body.
@MainActor
private func edgeGuideReach<V: View>(of type: V.Type) -> Bool {
    if let reach = type as? any EdgeGuideReaching.Type { return reach.mayReportEdgeOrCentreGuide }
    if type is any AlignmentGuideQuerying.Type || type is any AlignmentGuideProviding.Type { return true }
    if let wrapper = type as? any SingleContentWrapper.Type, keepsWrappedGeometry(wrapper) {
        return wrappedEdgeGuideReach(wrapper)
    }
    guard V.Body.self != Never.self, !(type is any Renderable.Type) else { return true }
    return mayReportEdgeOrCentreGuide(V.Body.self)
}

/// `keepsContentGeometry(_:)` of a wrapper type held as an existential.
@MainActor
private func keepsWrappedGeometry<W: SingleContentWrapper>(_ type: W.Type) -> Bool {
    keepsContentGeometry(type)
}

/// ``mayReportEdgeOrCentreGuide(_:)`` of a wrapper's content, the existential
/// opened.
@MainActor
private func wrappedEdgeGuideReach<W: SingleContentWrapper>(_: W.Type) -> Bool {
    mayReportEdgeOrCentreGuide(W.WrappedContent.self)
}

/// Whether a view of `Content`'s type, as a stack's whole content, lets the
/// stack report one of its edge or centre guides: only content that is
/// statically one view does (``AlignmentGuideQuery/staysInside(contentOf:)``).
@MainActor
func mayReportEdgeOrCentreGuide<Content: View>(ofStackContent _: Content.Type) -> Bool {
    staticViewListCount(Content.self) == 1 && mayReportEdgeOrCentreGuide(Content.self)
}

extension ChildView {
    /// Whether this child may have an explicit value for `query`'s guide:
    /// its witness, and for an edge or centre guide its type's reach
    /// (``mayReportEdgeOrCentreGuide(_:)``).
    func mayHaveExplicitGuide(_ query: AlignmentGuideQuery) -> Bool {
        guard providesAlignmentGuide else { return false }
        guard query.isEdgeOrCentre else { return true }
        func reach<V: View>(_: V) -> Bool { mayReportEdgeOrCentreGuide(V.self) }
        return reach(wrappedView)
    }
}

// MARK: - The types that say

/// A view type that answers ``mayReportEdgeOrCentreGuide(_:)`` itself: one
/// that answers the guide query itself (``AlignmentGuideQuerying``), so the
/// generic reading of a wrapper or a body does not describe it.
@MainActor
protocol EdgeGuideReaching {
    /// Whether a view of this type may report an edge or centre guide.
    static var mayReportEdgeOrCentreGuide: Bool { get }
}

extension _VStackCore: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool {
        TUIFoundation.mayReportEdgeOrCentreGuide(ofStackContent: Content.self)
    }
}

extension _HStackCore: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool {
        TUIFoundation.mayReportEdgeOrCentreGuide(ofStackContent: Content.self)
    }
}

extension _LayoutCore: EdgeGuideReaching {
    /// A layout of its own guides may report any; a stack layout of the
    /// framework's reports its one view's; any other layout's default merges
    /// only baselines and custom guides.
    static var mayReportEdgeOrCentreGuide: Bool {
        if L._definesExplicitAlignment || L.self is any ExplicitAlignmentForwarding.Type { return true }
        guard L.self is any PassesEveryGuideOfOneView.Type else { return false }
        return TUIFoundation.mayReportEdgeOrCentreGuide(ofStackContent: Content.self)
    }
}

extension ModifiedView: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Content.self) }
}

extension ConditionalView: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool {
        TUIFoundation.mayReportEdgeOrCentreGuide(TrueContent.self)
            || TUIFoundation.mayReportEdgeOrCentreGuide(FalseContent.self)
    }
}

extension Optional: EdgeGuideReaching where Wrapped: View {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Wrapped.self) }
}

extension FlexibleFrameView: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Content.self) }
}

extension OffsetView: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Content.self) }
}

extension PositionView: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Content.self) }
}

extension _BorderRings: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Bordered.self) }
}

extension OverlayModifier: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Base.self) }
}

extension BackgroundLayerModifier: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool { TUIFoundation.mayReportEdgeOrCentreGuide(Base.self) }
}
