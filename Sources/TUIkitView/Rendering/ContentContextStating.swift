//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentContextStating.swift
//
//  The context a wrapper that draws its content unchanged lays that content
//  out in, stated for a question that steps through the wrapper to ask it.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A ``DrawsContentUnchanged`` wrapper that states the context it lays its
/// content out in, so a question asked of its content through it — the
/// alignment-guide query, `explicitGuide(of:_:in:context:)` in TUIkitFoundation
/// — is asked in the context the content is measured and drawn in.
///
/// ## Why drawing its content unchanged is not enough
///
/// A wrapper that draws its content unchanged is its content's size, but its
/// content is not laid out in the context above it: an environment write —
/// `.lineLimit(1)`, `.controlSize(.large)`, `.textCase(.uppercase)`, a theme —
/// draws the same content at another size. A stack's guide is worked out by
/// measuring the stack's children, so a query that stepped through such a
/// write in the context above it measured them without the write, and placed
/// the guide where nothing is drawn: `VStack { a text that wraps; Text("B")
/// .alignmentGuide(.top) { _ in 0 } }.lineLimit(1)` reported its guide under
/// a first row three lines tall, where the drawn row is one.
///
/// ## What conforms
///
/// A wrapper conforms with the context its `sizeThatFits(proposal:context:)`
/// measures its content in — through the helper that measure uses, so the two
/// cannot drift — or, where that is the context it was given, through
/// ``HandsContentItsContext``. A guide stops at a wrapper that does not
/// conform (deviation L11): the safe default, as a wrong position is worse
/// than a documented stop. So a wrapper that starts writing to its content's
/// context must state it here, or drop its ``HandsContentItsContext`` claim.
@MainActor
package protocol ContentContextStating: DrawsContentUnchanged {
    /// The context this wrapper measures its content in, given the one it is
    /// measured in.
    func contentLayoutContext(_ context: RenderContext) -> RenderContext
}

/// A ``ContentContextStating`` wrapper that lays its content out in the
/// context it was given, unchanged: a lifecycle, event, gesture, focus or
/// registration modifier, whose measure is `measureChild(content, proposal:
/// proposal, context: context)`.
///
/// A claim, made type by type, and only by a wrapper whose measure hands its
/// content the context it was given — never a default for every
/// ``DrawsContentUnchanged`` wrapper, which may write to the environment.
@MainActor
package protocol HandsContentItsContext: ContentContextStating {}

extension HandsContentItsContext {
    /// `context`, as it was given.
    package func contentLayoutContext(_ context: RenderContext) -> RenderContext { context }
}
