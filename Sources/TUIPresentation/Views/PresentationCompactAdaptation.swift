//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationCompactAdaptation.swift
//
//  How a presentation adapts to a compact size class (decisions A21, with
//  B3's ruling: TUI follows a compact class an app writes, and changes no
//  default): `PresentationAdaptation`, the `presentationCompactAdaptation`
//  modifiers that state one on presented content, and the rules a popover and
//  a sheet follow.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - PresentationAdaptation

/// Strategies for adapting a presentation to a different size class —
/// SwiftUI's type of the same name.
///
/// A terminal's size classes are `.regular` unless an app writes `.compact`
/// into the environment (`\.horizontalSizeClass`, `\.verticalSizeClass`), and
/// it is then, as on iOS, that a presentation adapts.
public struct PresentationAdaptation: Sendable, Hashable {
    /// The strategies, as an `enum` the presenters switch over.
    enum Kind: Hashable {
        case automatic, none, popover, sheet, fullScreenCover
    }

    let kind: Kind

    /// The default adaptation for the size class: a popover becomes a sheet in
    /// a compact class.
    public static var automatic: Self { Self(kind: .automatic) }

    /// No adaptation: the presentation keeps its own form.
    public static var none: Self { Self(kind: .none) }

    /// A popover, where the presentation is one.
    public static var popover: Self { Self(kind: .popover) }

    /// A sheet.
    public static var sheet: Self { Self(kind: .sheet) }

    /// A full-screen cover.
    public static var fullScreenCover: Self { Self(kind: .fullScreenCover) }
}

// MARK: - presentationCompactAdaptation

/// Content that states how its presentation adapts to a compact size class.
@MainActor
protocol PresentationCompactAdapting {
    /// The adaptation in a horizontally compact size class.
    var horizontalAdaptation: PresentationAdaptation { get }
    /// The adaptation in a vertically compact size class.
    var verticalAdaptation: PresentationAdaptation { get }
}

/// The wrapper the `presentationCompactAdaptation` modifiers produce. Renders
/// and measures as its content; carrying the adaptation is its whole job, as
/// `interactiveDismissDisabled`'s does.
nonisolated struct _PresentationCompactAdaptationView<Content: View>: View, PresentationCompactAdapting {
    let content: Content
    let horizontalAdaptation: PresentationAdaptation
    let verticalAdaptation: PresentationAdaptation

    @MainActor var body: Never {
        fatalError("_PresentationCompactAdaptationView renders via Renderable")
    }
}

@MainActor extension _PresentationCompactAdaptationView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context)
    }
}

@MainActor extension _PresentationCompactAdaptationView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

@MainActor extension _PresentationCompactAdaptationView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
@MainActor extension _PresentationCompactAdaptationView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension _PresentationCompactAdaptationView: DrawsContentUnchanged {}

extension View {
    /// Specifies how to adapt a presentation to compact size classes —
    /// mirrors SwiftUI's `presentationCompactAdaptation(_:)`.
    ///
    /// Apply it to the presented **content**, as `presentationDetents` is:
    ///
    /// ```swift
    /// Button("Details") { showing = true }
    ///     .popover(isPresented: $showing) {
    ///         Details()
    ///             .presentationCompactAdaptation(.none)
    ///     }
    /// ```
    ///
    /// By default a popover becomes a sheet in a compact size class, and a
    /// sheet a full-screen cover in a vertically compact one. TUI's size
    /// classes are `.regular` unless the app writes `.compact` into the
    /// environment, so this changes nothing until it does.
    ///
    /// - Parameter adaptation: The adaptation in either compact size class.
    /// - Returns: The view, stating how its presentation adapts.
    nonisolated public func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View {
        _PresentationCompactAdaptationView(
            content: self, horizontalAdaptation: adaptation, verticalAdaptation: adaptation)
    }

    /// Specifies how to adapt a presentation to horizontally and vertically
    /// compact size classes — mirrors SwiftUI's
    /// `presentationCompactAdaptation(horizontal:vertical:)`.
    ///
    /// Where both size classes are compact, the vertical adaptation wins: a
    /// presentation is shortest of room vertically there (decisions A21).
    ///
    /// - Parameters:
    ///   - horizontalAdaptation: The adaptation in a horizontally compact
    ///     size class.
    ///   - verticalAdaptation: The adaptation in a vertically compact size
    ///     class.
    /// - Returns: The view, stating how its presentation adapts.
    nonisolated public func presentationCompactAdaptation(
        horizontal horizontalAdaptation: PresentationAdaptation, vertical verticalAdaptation: PresentationAdaptation
    ) -> some View {
        _PresentationCompactAdaptationView(
            content: self, horizontalAdaptation: horizontalAdaptation, verticalAdaptation: verticalAdaptation)
    }
}

// MARK: - How a presentation adapts

/// The adaptation `content` states for the compact size class it is in — the
/// vertical one where both are compact, a presentation being shortest of room
/// there — `.automatic` where it states none, or `nil` in a regular class,
/// where nothing adapts.
@MainActor
func compactAdaptation(
    of content: any View, horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?
) -> PresentationAdaptation? {
    let stated = presentationTrait((any PresentationCompactAdapting).self, of: content)
    if vertical == .compact { return stated?.verticalAdaptation ?? .automatic }
    if horizontal == .compact { return stated?.horizontalAdaptation ?? .automatic }
    return nil
}

/// The form a popover takes.
enum PopoverForm: Equatable {
    case popover, sheet, fullScreenCover
}

/// The form a popover whose content is `popover` takes under these size
/// classes.
///
/// In a regular class it stays a popover. In a compact one it takes the
/// adaptation its content states for that class (``compactAdaptation(of:horizontal:vertical:)``),
/// and `.automatic` is a sheet, as an iOS popover becomes one; `.none` and
/// `.popover` keep it a popover.
@MainActor
func popoverForm(
    of popover: any View, horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?
) -> PopoverForm {
    guard let adaptation = compactAdaptation(of: popover, horizontal: horizontal, vertical: vertical) else {
        return .popover
    }
    switch adaptation.kind {
    case .none, .popover: return .popover
    case .automatic, .sheet: return .sheet
    case .fullScreenCover: return .fullScreenCover
    }
}

/// The size classes a sheet is presented in, which decide whether it is
/// presented as a cover (``sheetIsCover(_:horizontal:vertical:)``) — read by
/// the view presenting it, and resolved against its content only once the
/// content is built, while it is presented.
struct PresentationSizeClasses {
    let horizontal: UserInterfaceSizeClass?
    let vertical: UserInterfaceSizeClass?
}

/// Whether a sheet whose content is `sheet` is presented as a full-screen
/// cover under these size classes.
///
/// In a vertically compact class it is, as SwiftUI's is: "In vertically
/// compact environments, such as iPhone in landscape orientation, a sheet
/// presentation automatically adapts to appear as a full-screen cover." The
/// content's adaptation says otherwise with `.none` or `.sheet` (`.popover`
/// too: a sheet has no anchor to become one at). In a horizontally compact
/// class alone it stays a sheet unless the content asks for a cover.
@MainActor
func sheetIsCover(
    _ sheet: any View, horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?
) -> Bool {
    guard let adaptation = compactAdaptation(of: sheet, horizontal: horizontal, vertical: vertical) else {
        return false
    }
    switch adaptation.kind {
    case .fullScreenCover: return true
    case .automatic: return vertical == .compact
    case .none, .sheet, .popover: return false
    }
}
