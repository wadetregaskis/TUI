//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlertActions.swift
//
//  How a dialog finds its buttons in the actions builder the app wrote.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Button Provider Protocol

/// A view that is a dialog's buttons, as given: a `Button`, or the actions
/// the dialog presenters wrap round the app's to add their own.
@MainActor
protocol ButtonProvider {
    /// The buttons this view is, resolved in `context`.
    func extractButtons(in context: RenderContext) -> [Button]
}

/// Identity tag for resolving a dialog's actions, a step in from the dialog,
/// so a view of the app's own among them keeps its `@State` apart.
private enum AlertActionsID {}

/// The `Button`s an alert's `actions` builder produced, in declaration order.
///
/// Resolved as ``Group/init(subviews:transform:)`` resolves members
/// (`subviewGroups(of:in:)`), so a button is found wherever it is written —
/// in an `if`/`else`, a `Group`, a `ForEach`, a view of the app's own — and
/// behind the modifiers written on it, as SwiftUI keeps "a Button … wherever in
/// the builder it was written". A modifier on a button is looked through, not
/// kept: the dialog draws the button itself. A member that is no button is
/// left out, as SwiftUI leaves out what an alert cannot show.
///
/// Shared by ``_AlertCore``, which lays them out, and
/// ``AlertPresentationModifier``, which needs the `.cancel`-role one to answer
/// Escape with.
@MainActor
func alertActionButtons(from view: some View, in context: RenderContext) -> [Button] {
    if let provider = view as? ButtonProvider { return provider.extractButtons(in: context) }
    let scope = context.withChildIdentity(type: AlertActionsID.self)
    var buttons: [Button] = []
    for group in subviewGroups(of: view, in: scope) {
        for member in group.members {
            var current = member.memberView
            while true {
                if let provider = current as? ButtonProvider {
                    buttons += provider.extractButtons(in: context)
                    break
                }
                if let wrapper = current as? any SingleContentWrapper {
                    current = wrapper.wrappedContent
                } else if let row = current as? any _ValueMemoWrapping {
                    // A `ForEach` row of an equatable element, memoized.
                    current = row.memoizedContent
                } else {
                    break
                }
            }
        }
    }
    return buttons
}

// MARK: - ButtonProvider Conformances

extension Button: ButtonProvider {
    func extractButtons(in context: RenderContext) -> [Button] {
        [self]
    }
}
