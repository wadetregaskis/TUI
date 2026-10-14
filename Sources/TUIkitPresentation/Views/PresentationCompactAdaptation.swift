//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationCompactAdaptation.swift
//
//  How a presentation adapts to a compact size class (decisions A21, with
//  B3's ruling: TUIkit follows a compact class an app writes, and changes no
//  default): `PresentationAdaptation`, the `presentationCompactAdaptation`
//  modifiers that state one on presented content, and the rule a popover
//  follows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

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
struct _PresentationCompactAdaptationView<Content: View>: View, PresentationCompactAdapting {
    let content: Content
    let horizontalAdaptation: PresentationAdaptation
    let verticalAdaptation: PresentationAdaptation

    var body: Never {
        fatalError("_PresentationCompactAdaptationView renders via Renderable")
    }
}

extension _PresentationCompactAdaptationView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
    }
}

extension _PresentationCompactAdaptationView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationCompactAdaptationView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationCompactAdaptationView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationCompactAdaptationView: DrawsContentUnchanged {}

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
    /// By default a popover becomes a sheet in a compact size class. TUIkit's
    /// size classes are `.regular` unless the app writes `.compact` into the
    /// environment, so this changes nothing until it does.
    ///
    /// - Parameter adaptation: The adaptation in either compact size class.
    /// - Returns: The view, stating how its presentation adapts.
    public func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View {
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
    public func presentationCompactAdaptation(
        horizontal horizontalAdaptation: PresentationAdaptation, vertical verticalAdaptation: PresentationAdaptation
    ) -> some View {
        _PresentationCompactAdaptationView(
            content: self, horizontalAdaptation: horizontalAdaptation, verticalAdaptation: verticalAdaptation)
    }
}

// MARK: - How a popover adapts

/// The form a popover takes.
enum PopoverForm: Equatable {
    case popover, sheet, fullScreenCover
}

/// The form a popover whose content is `popover` takes under these size
/// classes.
///
/// In a regular class it stays a popover. In a compact one it takes the
/// adaptation its content states for that class — the vertical one where both
/// are compact — and `.automatic` is a sheet, as an iOS popover becomes one;
/// `.none` and `.popover` keep it a popover.
@MainActor
func popoverForm(
    of popover: any View, horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?
) -> PopoverForm {
    let stated = presentationTrait((any PresentationCompactAdapting).self, of: popover)
    let adaptation: PresentationAdaptation
    if vertical == .compact {
        adaptation = stated?.verticalAdaptation ?? .automatic
    } else if horizontal == .compact {
        adaptation = stated?.horizontalAdaptation ?? .automatic
    } else {
        return .popover
    }
    switch adaptation.kind {
    case .automatic, .sheet: return .sheet
    case .fullScreenCover: return .fullScreenCover
    case .none, .popover: return .popover
    }
}
