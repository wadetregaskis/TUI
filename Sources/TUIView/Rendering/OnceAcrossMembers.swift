//  🖥️ TUI — A Terminal UI framework for Swift
//  OnceAcrossMembers.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Effect Wrappers on Multi-Member Content

/// A ``ContentRewrapping`` wrapper that performs an effect — `.onAppear`,
/// `.onDisappear`, `.task`, `.onChange` — and so must fire it ONCE for content
/// of several members, while still handing the members to the enclosing
/// container one by one.
///
/// Both halves are SwiftUI's, measured with an `NSHostingView` probe:
/// `HStack { Group { Text("A"); Text("B") }.onAppear {} }` lays A beside B,
/// as the same `Group` without the modifier does, and `.onAppear` on a
/// two-member `Group`, on a `ForEach` of three and `.task` on a `Group` each
/// fire once. A plain ``ContentRewrapping`` conformance gets the first half
/// and breaks the second: each copy of the wrapper would key its effect to the
/// member it stands around, and fire it once per member.
///
/// So a wrapper of this kind is first ANCHORED (``anchoringEffect(at:)``):
/// told the place its effect is keyed to drawn whole, at the identity the
/// content is being resolved at, which every copy around a member then
/// carries. The copies key the effect there, not at their member's identity,
/// and the lifecycle machinery that already tells a second sighting of a
/// token in one frame from a first fires it once: the first copy drawn
/// fires `.onAppear`, the rest find it appeared, and the token stays present
/// while ANY member is drawn — a lazy stack that windows the first member out
/// keeps it. Drawn whole the wrapper keys the same place, so content that
/// moves between being drawn whole and being taken apart fires nothing again.
///
/// Content that resolves to NO members — `Group { if false { … } }.onAppear`,
/// an empty `ForEach` with a `.task` that loads its rows — is handed over as
/// one child that draws nothing: a copy of the wrapper, anchored, around
/// ``_MemberlessEffectCarrier``. The effect still has somewhere to fire, as it
/// did before the wrapper handed members on.
@MainActor
package protocol OnceAcrossMembers: ContentRewrapping {
    /// This wrapper with its effect keyed to the place it keys it drawn whole
    /// at `context` — the context its content's members are being resolved
    /// in — so every copy ``ContentRewrapping/rewrapping(_:)`` makes from it
    /// shares that place. A wrapper already anchored keeps its anchor: a copy
    /// around a member that is itself taken apart further is still the
    /// effect written once.
    func anchoringEffect(at context: RenderContext) -> Self
}

extension OnceAcrossMembers {
    /// The content's members, each inside a copy of this wrapper anchored at
    /// `context`; where there are none, one anchored copy that draws nothing.
    package func anchoredMembers(_ members: [ChildView], context: RenderContext) -> [ChildView] {
        let anchored = anchoringEffect(at: context)
        guard !members.isEmpty else { return [ChildView(anchored.rewrapping(_MemberlessEffectCarrier()))] }
        return members.map { $0.rewrapped(by: anchored) }
    }
}

/// Child resolution through an effect wrapper: ``ContentRewrapping``'s, with
/// the copies anchored (``OnceAcrossMembers``). The other three members of
/// ``ChildViewProvider`` are ``ContentRewrapping``'s unchanged.
extension ChildViewProvider where Self: OnceAcrossMembers, WrappedContent: ChildViewProvider {
    /// The content's members, each one back inside a copy of this wrapper
    /// whose effect is keyed to one place for all of them.
    package func childViews(context: RenderContext) -> [ChildView] {
        anchoredMembers(wrappedContent.childViews(context: membersContext(context)), context: context)
    }
}

/// What an effect wrapper whose content has no members stands around, handed
/// to the container as one child (``OnceAcrossMembers``): it draws nothing and
/// takes no cells, as the content would not.
///
/// Not the content itself, nor an `EmptyView`, because each of those is a
/// ``ChildViewProvider`` — of none — and the wrapper around it would be one
/// too: a walk that took the child apart again would be handed the same child
/// back. This is a leaf, so the child is one view wherever it goes.
nonisolated package struct _MemberlessEffectCarrier: View {
    package init() {}

    @MainActor package var body: Never {
        fatalError("_MemberlessEffectCarrier renders via Renderable")
    }
}

@MainActor extension _MemberlessEffectCarrier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer { FrameBuffer() }
}

@MainActor extension _MemberlessEffectCarrier: Layoutable {
    /// It occupies no cells.
    package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize { ViewSize.fixed(0, 0) }
}
