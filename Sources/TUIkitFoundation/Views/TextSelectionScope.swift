//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSelectionScope.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TextSelectionScope

/// What a drag selection keeps to: a bordered container's interior, or the
/// whole pane it started in — given to ``View/textSelectionScope(_:)``.
///
/// TUIkit-specific. SwiftUI keeps a selection inside one `Text`; TUIkit
/// selects what is drawn (see ``View/textSelection(_:)``), so where a drag
/// may run is a question SwiftUI never has to answer.
public enum TextSelectionScope: Sendable, Hashable {
    /// A drag that starts inside a bordered container — `.border()`, `Box`,
    /// `Card`, `Panel`, `GroupBox`, a dialog, an alert — selects within the
    /// container's interior: its border, its title and the page around it
    /// are left out. The innermost container under the press is the one, so a
    /// box inside a box keeps to the inner one. The default.
    ///
    /// A drag that goes on past the container — more than 3 rows above or
    /// below its interior, or more than 6 columns beside it — widens to what
    /// the container sits in (the box around it, an enabled
    /// ``View/textSelection(_:)``, or the pane), and stays widened until the
    /// release. Overshooting the border by a row or two on the way to the
    /// container's last line keeps to the container.
    ///
    /// A drag that starts on a container's border, or outside it, is not the
    /// container's, and selects across it as ``pane`` does.
    case container

    /// A drag selects within the pane it started in — a scroll view, a split
    /// view's column, or the content area — crossing the borders of the
    /// containers inside it.
    case pane
}

extension View {
    /// Sets what a drag selection inside this view keeps to: the interior of
    /// the bordered container it starts in (``TextSelectionScope/container``,
    /// the default), or the pane (``TextSelectionScope/pane``).
    ///
    /// TUIkit-specific. Applies to the containers in this view and inside it,
    /// so put it on the app's root view to select across every container's
    /// border, or on one container to free that one alone; a
    /// ``View/textSelection(_:)`` inside still keeps its selection to itself.
    ///
    /// ```swift
    /// VStack {
    ///     Text("Release notes").bold()
    ///     Text(notes)
    /// }
    /// .border()
    /// .textSelectionScope(.pane)  // a drag runs on past the border
    /// ```
    ///
    /// - Parameter scope: What a selection begun inside keeps to.
    /// - Returns: A view whose containers keep a selection as `scope` says.
    public func textSelectionScope(_ scope: TextSelectionScope) -> some View {
        environment(\.textSelectionScope, scope)
    }
}

// MARK: - Environment

/// `@usableFromInline`, so internal rather than `private`, with its default:
/// the `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct TextSelectionScopeKey: EnvironmentKey {
    @usableFromInline static let defaultValue = TextSelectionScope.container
}

extension EnvironmentValues {
    /// What a drag selection keeps to (``View/textSelectionScope(_:)``): read
    /// by a bordered container, which files its interior as a scope only
    /// under ``TextSelectionScope/container``.
    @inlinable
    package var textSelectionScope: TextSelectionScope {
        get { self[TextSelectionScopeKey.self] }
        set { self[TextSelectionScopeKey.self] = newValue }
    }
}

// MARK: - The dispatcher's scopes

/// What a selection scope's region says about a selection begun under it, as
/// the mouse dispatcher files it.
package enum SelectionScope: Sendable, Equatable {
    /// A ``View/textSelection(_:)`` of ``TextSelectability/enabled``: text
    /// selects, kept to the scope.
    case enabled
    /// A ``View/textSelection(_:)`` of ``TextSelectability/disabled``: nothing
    /// selects.
    case disabled
    /// A bordered container's interior (``TextSelectionScope/container``):
    /// whether text selects is left to the scopes around it, and where it
    /// does, the selection keeps to the interior.
    case interior

    /// Whether a selection begun under the scope keeps to its rectangle.
    var confinesSelection: Bool { self != .disabled }
}
