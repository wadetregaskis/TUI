//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationInteraction.swift
//
//  `presentationBackgroundInteraction(_:)` and
//  `presentationContentInteraction(_:)`, in the values a terminal sheet
//  already honours.
//
//  Both modifiers return the view unchanged, and neither is a stub: the values
//  that exist here are the ones that describe what a presentation does —
//  the page behind it is inert, and its content scrolls rather than resizing
//  it. The values that would ask for something else — interacting with the
//  page behind a sheet, a swipe that resizes a sheet between its detents — are
//  left out, so asking for them fails to compile. (See
//  `MediumGuaranteedModifiers.swift` for the line between a guarantee kept and
//  a request dropped, and decisions A19 for what the rest would take.)
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - PresentationBackgroundInteraction

/// The kinds of interaction available to views behind a presentation. Mirrors
/// SwiftUI's `PresentationBackgroundInteraction`, in the values a terminal
/// honours.
///
/// SwiftUI's `.enabled` and `.enabled(upThrough:)` are absent: the page behind
/// a presentation is drawn as an inert, dimmed backdrop, so they would be
/// requests nothing could act on.
public struct PresentationBackgroundInteraction: Sendable {
    private enum Kind: Sendable {
        case automatic, disabled
    }

    private let kind: Kind

    /// The default background interaction for the presentation: none.
    public static var automatic: Self { Self(kind: .automatic) }

    /// People can't interact with the view behind a presentation.
    public static var disabled: Self { Self(kind: .disabled) }
}

// MARK: - PresentationContentInteraction

/// A behavior that you can use to influence how a presentation responds to
/// swipe gestures. Mirrors SwiftUI's `PresentationContentInteraction`, in the
/// values a terminal honours.
///
/// SwiftUI's `.resizes` is absent: a terminal sheet has no gesture that
/// resizes it between its detents — the `selection:` binding of
/// ``View/presentationDetents(_:selection:)`` is how it changes size — so a
/// request to prefer resizing would be one nothing could act on.
public struct PresentationContentInteraction: Equatable, Sendable {
    private enum Kind: Equatable, Sendable {
        case automatic, scrolls
    }

    private let kind: Kind

    /// The default swipe behavior for the presentation: its content scrolls.
    public static var automatic: Self { Self(kind: .automatic) }

    /// A behavior that prioritizes scrolling the content of a presentation
    /// when swiping, rather than resizing the presentation.
    public static var scrolls: Self { Self(kind: .scrolls) }
}

// MARK: - Modifiers

extension View {
    /// Controls whether people can interact with the view behind a
    /// presentation. Mirrors SwiftUI's `presentationBackgroundInteraction(_:)`.
    ///
    /// Both values here say what a presentation already does: the page behind
    /// a sheet, cover or popover is inert while it is up.
    ///
    /// - Parameter interaction: How people can interact with the view behind
    ///   the presentation.
    /// - Returns: This view, unchanged.
    public func presentationBackgroundInteraction(
        _ interaction: PresentationBackgroundInteraction
    ) -> some View {
        self
    }

    /// Configures the behavior of swipe gestures on a presentation. Mirrors
    /// SwiftUI's `presentationContentInteraction(_:)`.
    ///
    /// Both values here say what a presentation already does: a wheel or a
    /// key scrolls its content — an over-tall sheet scrolls inside its
    /// height — and nothing resizes the sheet.
    ///
    /// - Parameter behavior: The requested behavior.
    /// - Returns: This view, unchanged.
    public func presentationContentInteraction(_ behavior: PresentationContentInteraction) -> some View {
        self
    }
}
