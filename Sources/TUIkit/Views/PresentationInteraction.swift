//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationInteraction.swift
//
//  `presentationBackgroundInteraction(_:)` and
//  `presentationContentInteraction(_:)`.
//
//  The content interaction decides what the wheel does over a detented sheet
//  with a grabber: scroll its content, resize it first, or resize it once its
//  content can scroll no further. The background interaction, so far, only in
//  the values that describe what a presentation does — the page behind it is
//  inert — and returns the view unchanged; interacting with the page behind a
//  sheet is left out, so asking for it fails to compile. (See
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
/// swipe gestures. Mirrors SwiftUI's `PresentationContentInteraction`.
///
/// A terminal's swipe is the wheel. What it does over a detented sheet that
/// has a grabber (``View/presentationDragIndicator(_:)``) — scroll the content,
/// or move the sheet between its detents — is what this decides; a sheet with
/// no grabber has nothing to resize, and its content scrolls.
public struct PresentationContentInteraction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case automatic, scrolls, resizes
    }

    let kind: Kind

    /// The default swipe behavior for the presentation: its content scrolls,
    /// and the wheel never resizes it.
    ///
    /// SwiftUI's default on iOS grows a resizable sheet before its content
    /// scrolls. Here the wheel stays the content's, as it is everywhere else
    /// in a terminal app, and the grabber resizes the sheet; ask for
    /// ``resizes`` for iOS's order.
    public static var automatic: Self { Self(kind: .automatic) }

    /// A behavior that prioritizes scrolling the content of a presentation
    /// when swiping, rather than resizing the presentation: the wheel scrolls
    /// the content, and moves the sheet to its next detent only where the
    /// content can scroll no further that way — or has nothing to scroll.
    public static var scrolls: Self { Self(kind: .scrolls) }

    /// A behavior that prioritizes resizing a presentation when swiping,
    /// rather than scrolling the content of the presentation: the wheel
    /// pulled down grows the sheet to its next larger detent, and the content
    /// scrolls only once the sheet is at its largest. Pushed up, the wheel
    /// scrolls the content back first, and shrinks the sheet once the content
    /// is at its top, as a swipe down does on a phone.
    public static var resizes: Self { Self(kind: .resizes) }
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
    /// Apply it to the sheet's **content**, with its detents. A terminal's
    /// swipe is the wheel, and this decides what the wheel does over a
    /// detented sheet with a grabber (``View/presentationDragIndicator(_:)``):
    /// ``PresentationContentInteraction/automatic`` scrolls the content only,
    /// ``PresentationContentInteraction/scrolls`` scrolls it and moves the
    /// sheet to its next detent where the content can scroll no further, and
    /// ``PresentationContentInteraction/resizes`` moves the sheet first. The
    /// wheel moves the sheet one detent at a time, at most one every quarter
    /// of a second, so one turn of a wheel or flick of a trackpad does not
    /// sweep through every detent; the ticks in between are spent, and do not
    /// scroll the content either.
    ///
    /// The grabber's keys resize the sheet whatever this says, and a sheet
    /// with no grabber — one detent, or the indicator hidden — has nothing to
    /// resize: its content scrolls.
    ///
    /// - Parameter behavior: The requested behavior.
    public func presentationContentInteraction(_ behavior: PresentationContentInteraction) -> some View {
        _PresentationContentInteractionView(content: self, contentInteraction: behavior)
    }
}

// MARK: - The content interaction, as a trait

/// Content that has said what a swipe — the wheel — does over its sheet.
@MainActor
protocol PresentationContentInteractionProviding {
    /// The behaviour the content asked for.
    var contentInteraction: PresentationContentInteraction { get }
}

/// The wrapper ``View/presentationContentInteraction(_:)`` produces. Renders
/// and measures as its content; carrying the behaviour is its whole job.
struct _PresentationContentInteractionView<Content: View>: View, PresentationContentInteractionProviding {
    let content: Content
    let contentInteraction: PresentationContentInteraction

    var body: Never {
        fatalError("_PresentationContentInteractionView renders via Renderable")
    }
}

extension _PresentationContentInteractionView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _PresentationContentInteractionView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationContentInteractionView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationContentInteractionView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationContentInteractionView: DrawsContentUnchanged {}
