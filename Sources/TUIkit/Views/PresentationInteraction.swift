//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationInteraction.swift
//
//  `presentationBackgroundInteraction(_:)` and
//  `presentationContentInteraction(_:)`.
//
//  The content interaction decides what the wheel does over a detented sheet
//  with a grabber: scroll its content, resize it first, or resize it once its
//  content can scroll no further. The background interaction decides whether
//  the page behind a detented sheet stays live: the sheet docks at the bottom
//  of the content area and the page is laid out in the rows above it, a pane
//  beside the sheet (decisions A19, design C).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - PresentationBackgroundInteraction

/// The kinds of interaction available to views behind a presentation. Mirrors
/// SwiftUI's `PresentationBackgroundInteraction`.
///
/// A terminal has no room to draw a live page UNDER a sheet — whatever the
/// sheet hid, Tab and the arrow keys could still reach — so where the page
/// behind a detented sheet is live, the sheet docks at the bottom of the
/// content area and the page is laid out in the rows above it: a pane beside
/// the sheet, as the panes of a ``VSplitView`` are (decisions A19).
public struct PresentationBackgroundInteraction: Sendable {
    enum Kind: Sendable {
        case automatic, disabled
        /// Live, at detents no taller than `upThrough`'s; at every detent when
        /// `nil`.
        case enabled(upThrough: PresentationDetent?)
    }

    let kind: Kind

    /// The default background interaction for the presentation: none.
    public static var automatic: Self { Self(kind: .automatic) }

    /// People can't interact with the view behind a presentation.
    public static var disabled: Self { Self(kind: .disabled) }

    /// People can interact with the view behind a presentation.
    ///
    /// A sheet with detents docks at the bottom of the content area, and the
    /// page is laid out in the rows above it, live: the focus moves between
    /// the two with Tab, and each has its own keys. A sheet without detents —
    /// whose height only its content knows — stays a modal dialog over the
    /// page, as an undetented sheet covers the page on a phone.
    public static var enabled: Self { Self(kind: .enabled(upThrough: nil)) }

    /// People can interact with the view behind a presentation up through a
    /// specified detent.
    ///
    /// At detents larger than the one you specify, the sheet is a modal again:
    /// the page behind it is dimmed and inert, and the sheet takes the focus.
    /// Compared by height, in the rows the detents come to in this terminal.
    ///
    /// - Parameter detent: The largest detent at which people can interact
    ///   with the view behind the presentation.
    public static func enabled(upThrough detent: PresentationDetent) -> Self {
        Self(kind: .enabled(upThrough: detent))
    }

    /// Whether the page behind a sheet resting `height` rows tall, in a
    /// content area `extent` rows tall, stays live.
    ///
    /// `upThrough` is compared by the height it comes to, as SwiftUI words it
    /// ("at detents larger than…"); a custom detent that is not available
    /// there lets nothing through.
    @MainActor
    func letsThePageThrough(atHeight height: Int, extent: Int, environment: EnvironmentValues) -> Bool {
        switch kind {
        case .automatic, .disabled:
            return false
        case .enabled(let upThrough):
            guard let upThrough else { return true }
            guard let limit = upThrough.resolved(in: extent, environment: environment) else { return false }
            return height <= limit
        }
    }
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
    /// Apply it to the sheet's **content**, with its detents. With
    /// ``PresentationBackgroundInteraction/enabled`` the sheet docks at the
    /// bottom of the content area and the page is laid out in the rows above
    /// it — shorter by the sheet's height, as a terminal resize would make it
    /// — and stays live: Tab moves the focus between the page and the sheet,
    /// a click on the page reaches it, and the keys are the pane's the focus
    /// is in (Escape on the page is the page's). The page is never drawn under
    /// the sheet, so nothing the focus can reach is hidden.
    ///
    /// The sheet is a modal again — over a dimmed, inert page — at a detent
    /// taller than ``PresentationBackgroundInteraction/enabled(upThrough:)``
    /// allows, when the page would keep fewer than three rows, when the sheet
    /// would be fewer than three, and for a sheet without detents. A cover has
    /// nothing behind it and a popover is already beside a live page; both
    /// ignore it.
    ///
    /// - Parameter interaction: How people can interact with the view behind
    ///   the presentation.
    public func presentationBackgroundInteraction(
        _ interaction: PresentationBackgroundInteraction
    ) -> some View {
        _PresentationBackgroundInteractionView(content: self, backgroundInteraction: interaction)
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

// MARK: - The background interaction, as a trait

/// Content that has said whether the page behind its sheet stays live.
@MainActor
protocol PresentationBackgroundInteractionProviding {
    /// The interaction the content asked for.
    var backgroundInteraction: PresentationBackgroundInteraction { get }
}

/// The wrapper ``View/presentationBackgroundInteraction(_:)`` produces. Renders
/// and measures as its content; carrying the interaction is its whole job.
struct _PresentationBackgroundInteractionView<Content: View>: View, PresentationBackgroundInteractionProviding {
    let content: Content
    let backgroundInteraction: PresentationBackgroundInteraction

    var body: Never {
        fatalError("_PresentationBackgroundInteractionView renders via Renderable")
    }
}

extension _PresentationBackgroundInteractionView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _PresentationBackgroundInteractionView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationBackgroundInteractionView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationBackgroundInteractionView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationBackgroundInteractionView: DrawsContentUnchanged {}
