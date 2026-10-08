//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationTraits.swift
//
//  Things a sheet's CONTENT says about how it should be presented, read by the
//  thing presenting it: how tall to be (``PresentationDetent``), and whether
//  the reader is allowed to dismiss it by hand (`InteractiveDismissDisabled.swift`).
//
//  All of them travel the same way — a wrapper view the presenter finds by a
//  static conformance check, not a preference. A preference is only readable
//  after the subtree renders, and every one of these has to be known BEFORE
//  it: the detent is the height being rendered into, and the Escape item is
//  registered on the status bar before the content exists.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Looking through the wrappers

/// A trait wrapper that can be seen past, so a second trait applied beneath it
/// is still found.
///
/// Without this each trait would have to be the presented content's outermost
/// view, and applying two would silently drop whichever ended up inner —
/// `.presentationDetents([.medium]).interactiveDismissDisabled()` and the same
/// pair the other way round would behave differently, for no reason a reader
/// could see.
@MainActor
package protocol PresentationTraitWrapper {
    /// The view directly beneath this wrapper.
    var presentationTraitContent: any View { get }
}

/// The outermost `T` in a chain of presentation-trait wrappers, if there is one.
///
/// Each step strictly descends one wrapper, so the walk terminates on any tree.
@MainActor
package func presentationTrait<T>(_ type: T.Type, of view: any View) -> T? {
    var current = view
    while true {
        if let match = current as? T { return match }
        guard let wrapper = current as? any PresentationTraitWrapper else { return nil }
        current = wrapper.presentationTraitContent
    }
}

/// Every `T` in a chain of presentation-trait wrappers, outermost first — for a
/// trait whose statements combine rather than the outermost winning.
@MainActor
func presentationTraits<T>(_ type: T.Type, of view: any View) -> [T] {
    var found: [T] = []
    var current = view
    while true {
        if let match = current as? T { found.append(match) }
        guard let wrapper = current as? any PresentationTraitWrapper else { return found }
        current = wrapper.presentationTraitContent
    }
}

// The `@ViewBuilder`'s own bookkeeping is looked through as well. `if` and
// `if`/`else` in a sheet's builder are ordinary things to write, and neither
// puts a view in the tree that the author can see — so a trait "applied to the
// content" would be invisible for a reason nobody could deduce from their own
// source. That is the whole list: these two, and the trait wrappers themselves.
// Anything the author actually wrote (an `AnyView`, a `Group`, a view of their
// own) still has to be inside the trait, which is the documented rule.

extension ConditionalView: PresentationTraitWrapper {
    package var presentationTraitContent: any View {
        switch self {
        case .trueContent(let view): view
        case .falseContent(let view): view
        }
    }
}

extension Optional: PresentationTraitWrapper where Wrapped: View {
    package var presentationTraitContent: any View { self ?? EmptyView() }
}

// MARK: - interactiveDismissDisabled()

/// Content that has asked not to be dismissed by hand.
@MainActor
package protocol InteractiveDismissDisabling {
    /// Whether Escape and an outside click should stop closing the presentation.
    var interactiveDismissIsDisabled: Bool { get }
}
