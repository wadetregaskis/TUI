//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationSizing.swift
//
//  How big a sheet is: the size its content is proposed, and how the sheet
//  follows its content — SwiftUI's `PresentationSizing`, in cells.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - The protocol

/// A type that defines the size of the presentation content and how the
/// presentation size adjusts to its content's size changing.
///
/// A sheet's content is proposed the size its sizing returns, and the sheet
/// adopts it: its outermost box — a ``Dialog``, ``Panel``, ``Card`` or
/// `.border()` — takes the proposed width and height, enclosing what its
/// content leaves as empty interior, as it takes a detent's height
/// (``View/presentationDetents(_:)``). An axis proposed `nil` is fitted: the
/// sheet is as big as its content there. Boxes stacked in a ``VStack`` or
/// side by side in an ``HStack`` share the proposal, as flexible views share a
/// stack, and boxes in a ``ScrollView`` are their content's size along the
/// axes it scrolls, as it offers its content as much as it wants there, and
/// take the sheet's size across them (a vertical scroll view's boxes span the
/// sheet's width). Anywhere else — a
/// ``ZStack``, a ``Grid``, a lazy stack or lazy grid outside a scroll view —
/// each box takes the whole proposal. Content with no box is offered the
/// proposal; a detented sheet of it is laid on blank cells of its detent's
/// height, so it is as tall as the detent.
///
/// You don't need to define your own version of this protocol. The system
/// sizings ``PresentationSizing/form``, ``PresentationSizing/page`` and
/// ``PresentationSizing/fitted`` adapt to the terminal's size; to define your
/// own, first consider ``PresentationSizing/sticky(horizontal:vertical:)`` and
/// ``PresentationSizing/fitted(horizontal:vertical:)``. A sizing of your own
/// proposes a size in cells:
///
/// ```swift
/// struct SquareSizing: PresentationSizing {
///     func proposedSize(
///         for root: PresentationSizingRoot, context: PresentationSizingContext
///     ) -> ProposedSize {
///         .init(width: 40, height: 20)
///     }
/// }
/// ```
public protocol PresentationSizing {
    /// The size to propose to the presentation's content.
    ///
    /// - Parameters:
    ///   - root: The presentation's content, to measure.
    ///   - context: Contextual information about the presentation.
    /// - Returns: The proposal, in cells; `nil` on an axis fits the content.
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize
}

/// A proxy to a view provided to the presentation with a defined presentation
/// size.
public struct PresentationSizingRoot {
    /// Measures the presentation's content.
    let measure: (ProposedSize) -> ViewSize

    /// Asks the subview for its size.
    ///
    /// - Parameter proposal: The size proposed, in cells.
    /// - Returns: The size of the presentation's content view given
    ///   `proposal` — a ``ViewSize``, as ``LayoutSubview`` answers, in cells
    ///   and saying whether the content fills an axis.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        measure(proposal)
    }
}

/// Contextual information about a presentation.
///
/// The properties of a `PresentationSizingContext` can influence what size is
/// proposed to a presentation. It has no public members, as SwiftUI's has none.
public struct PresentationSizingContext {
    /// The area the presentation is shown in: the terminal's width by the
    /// content area's height.
    let area: CellSize
}

// MARK: - The system sizings

/// The default presentation sizing: today's sheet, as big as its content.
///
/// macOS 15.8 resolves `.automatic` to `.form.fitted(horizontal: false,
/// vertical: true)` (measured: a filling sheet 470 points wide by its
/// content's height); a terminal sheet has always fitted its content, and
/// `.automatic` keeps it so, so no sheet that does not ask changes size.
public struct AutomaticPresentationSizing: PresentationSizing {
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        .unspecified
    }
}

/// A presentation sizing dictated by the ideal size of the content.
public struct FittedPresentationSizing: PresentationSizing {
    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        .unspecified
    }
}

/// A presentation sizing appropriate for forms, and slightly less wide than
/// `.page`: 64 columns by 25 rows, or the terminal's own width or the content
/// area's height where they are less — about the 470-by-400-point sheet macOS
/// 15.8 proposes for `.form` (measured).
public struct FormPresentationSizing: PresentationSizing {
    /// The columns a form sheet is proposed.
    static let width = 64

    /// The rows a form sheet is proposed.
    static let height = 25

    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        ProposedSize(width: min(Self.width, context.area.width), height: min(Self.height, context.area.height))
    }
}

/// A presentation sizing roughly the size of a page of paper, appropriate for
/// informational or compositional content: 96 columns, or the terminal's
/// width where it is less, by the content area's height.
public struct PagePresentationSizing: PresentationSizing {
    /// The columns a page sheet is proposed.
    static let width = 96

    public func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        ProposedSize(width: min(Self.width, context.area.width), height: context.area.height)
    }
}

extension PresentationSizing where Self == AutomaticPresentationSizing {
    /// The default presentation sizing: the sheet fits its content.
    public static var automatic: AutomaticPresentationSizing { AutomaticPresentationSizing() }
}

extension PresentationSizing where Self == FittedPresentationSizing {
    /// The presentation sizing is dictated by the ideal size of the content.
    public static var fitted: FittedPresentationSizing { FittedPresentationSizing() }
}

extension PresentationSizing where Self == FormPresentationSizing {
    /// The size is appropriate for forms and slightly less wide than `.page`.
    public static var form: FormPresentationSizing { FormPresentationSizing() }
}

extension PresentationSizing where Self == PagePresentationSizing {
    /// The size is roughly the size of a page of paper, appropriate for
    /// informational or compositional content.
    public static var page: PagePresentationSizing { PagePresentationSizing() }
}

// MARK: - Fitted and sticky

/// What a sizing says about which axes keep their largest size.
protocol _StickyPresentationSizing {
    var stickyAxes: (horizontal: Bool, vertical: Bool) { get }
}

/// The sizing `fitted(horizontal:vertical:)` returns.
struct _FittingPresentationSizing<Base: PresentationSizing>: PresentationSizing, _StickyPresentationSizing {
    let base: Base
    let horizontal: Bool
    let vertical: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        let proposal = base.proposedSize(for: root, context: context)
        return ProposedSize(width: horizontal ? nil : proposal.width, height: vertical ? nil : proposal.height)
    }

    var stickyAxes: (horizontal: Bool, vertical: Bool) {
        (base as? any _StickyPresentationSizing)?.stickyAxes ?? (horizontal: false, vertical: false)
    }
}

/// The sizing `sticky(horizontal:vertical:)` returns.
struct _KeepingPresentationSizing<Base: PresentationSizing>: PresentationSizing, _StickyPresentationSizing {
    let base: Base
    let horizontal: Bool
    let vertical: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        base.proposedSize(for: root, context: context)
    }

    var stickyAxes: (horizontal: Bool, vertical: Bool) {
        let inner = (base as? any _StickyPresentationSizing)?.stickyAxes ?? (horizontal: false, vertical: false)
        return (inner.horizontal || horizontal, inner.vertical || vertical)
    }
}

extension PresentationSizing {
    /// Modifies self to fit the content in the specified dimensions: the
    /// presentation is as big as its content there, whatever self proposes.
    ///
    /// - Parameters:
    ///   - horizontal: Whether to fit the content's width.
    ///   - vertical: Whether to fit the content's height.
    /// - Returns: A modified version of self.
    public func fitted(horizontal: Bool, vertical: Bool) -> some PresentationSizing {
        _FittingPresentationSizing(base: self, horizontal: horizontal, vertical: vertical)
    }

    /// Modifies self to be sticky in the specified dimensions — growing, but
    /// not shrinking.
    ///
    /// The presentation keeps the largest size it has had in a sticky
    /// dimension for as long as it is presented; presented again, it starts
    /// over.
    ///
    /// ```swift
    /// ContentView()
    ///     .sheet(isPresented: $presentSheet) {
    ///         MyDynamicSheetContent()
    ///             .presentationSizing(.form.sticky(horizontal: false, vertical: true))
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - horizontal: Whether to maintain the largest size horizontally.
    ///   - vertical: Whether to maintain the largest size vertically.
    /// - Returns: A modified version of self sticking to the dimensions
    ///   specified.
    public func sticky(horizontal: Bool = false, vertical: Bool = false) -> some PresentationSizing {
        _KeepingPresentationSizing(base: self, horizontal: horizontal, vertical: vertical)
    }
}

// MARK: - Saying it

/// Content that names how big its presentation is.
@MainActor
protocol PresentationSizingProviding {
    var sizing: any PresentationSizing { get }
}

/// The wrapper ``View/presentationSizing(_:)`` produces. Renders and measures
/// as its content; carrying the sizing is its whole job, read by the presenter
/// before the content renders — see ``presentationTrait(_:of:)``.
struct _PresentationSizingView<Content: View>: View, PresentationSizingProviding {
    let content: Content
    let sizing: any PresentationSizing

    var body: Never {
        fatalError("_PresentationSizingView renders via Renderable")
    }
}

extension _PresentationSizingView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
    }
}

extension _PresentationSizingView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationSizingView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

extension _PresentationSizingView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

extension _PresentationSizingView: DrawsContentUnchanged {}
/// Measures its content in the context it is given, so an alignment guide
/// inside it is asked through it — see `HandsContentItsContext`.
extension _PresentationSizingView: HandsContentItsContext {}

extension View {
    /// Sets the sizing of the containing presentation.
    ///
    /// Apply it to a sheet's **content**: the content is proposed the size
    /// `sizing` returns, and the sheet adopts it — its outermost box takes the
    /// proposed size, and an axis the sizing fits is as big as the content. The
    /// default is `.automatic`, the sheet fitting its content.
    ///
    /// ```swift
    /// .sheet(isPresented: $presentInfo) {
    ///     FlowerFacts()
    ///         .presentationSizing(.page.fitted(horizontal: false, vertical: true).sticky(vertical: true))
    /// }
    /// ```
    ///
    /// A detent (``View/presentationDetents(_:)``) names the sheet's height
    /// and wins over the sizing's. A full-screen cover is the content area and
    /// takes no sizing.
    ///
    /// - Parameter sizing: The sizing of the presentation.
    /// - Returns: A view whose presentation takes `sizing`.
    public func presentationSizing(_ sizing: some PresentationSizing) -> some View {
        _PresentationSizingView(content: self, sizing: sizing)
    }
}

// MARK: - Resolving it

/// The largest size a sticky sizing has given a sheet while it stays
/// presented, kept in the presenter's state, and emptied when it closes or
/// is presented for another item (`ModalPresentationModifier.startOver(context:)`).
/// A class, changed in place: the sheet draws at the size it records on the
/// frame it records it, so neither growing it nor emptying it on close needs
/// another frame, as a state write would ask for.
@MainActor
final class KeptSheetSize {
    var size: CellSize?
}

/// The size a sheet's sizing gives it, applied to the context it renders in:
/// a proposed width and height become the sheet's available space and the
/// size its box takes (``EnvironmentValues/sheetProposedWidth``,
/// ``EnvironmentValues/sheetDetentHeight``). A sticky axis takes the largest
/// size `kept` has seen and grows it.
///
/// - Parameters:
///   - sizing: The content's sizing.
///   - content: The sheet's content, measured for a fitted, sticky axis.
///   - context: The sheet's context, changed in place.
///   - hasDetent: Whether a detent already named the height, which wins.
///   - kept: The largest size so far, in the presenter's state, for a sticky
///     sizing.
/// - Returns: The height the sheet is capped to, when the sizing proposed one.
@MainActor
func applyPresentationSizing(
    _ sizing: any PresentationSizing, of content: some View, to context: inout RenderContext,
    hasDetent: Bool, kept: KeptSheetSize?
) -> Int? {
    let area = CellSize(width: max(1, context.availableWidth), height: max(1, context.availableHeight))
    let measuring = context
    let root = PresentationSizingRoot { proposal in measureChild(content, proposal: proposal, context: measuring) }
    let proposal = sizing.proposedSize(for: root, context: PresentationSizingContext(area: area))
    var width = proposal.width.map { min(max(1, $0), area.width) }
    var height = proposal.height.map { min(max(1, $0), area.height) }

    let sticky = (sizing as? any _StickyPresentationSizing)?.stickyAxes ?? (horizontal: false, vertical: false)
    if let kept, sticky.horizontal || sticky.vertical {
        // The size the sheet would take now: the proposal where there is one,
        // the content's own where the axis fits it.
        let fitted =
            width == nil || height == nil
            ? root.sizeThatFits(ProposedSize(width: width ?? area.width, height: height)) : nil
        let now = CellSize(width: width ?? fitted?.width ?? 0, height: height ?? fitted?.height ?? 0)
        let largest = CellSize(
            width: max(now.width, kept.size?.width ?? 0), height: max(now.height, kept.size?.height ?? 0))
        kept.size = largest
        if sticky.horizontal { width = min(largest.width, area.width) }
        if sticky.vertical { height = min(largest.height, area.height) }
    }

    if let width {
        context.availableWidth = width
        context.environment.sheetProposedWidth = width
    }
    guard let height, !hasDetent else { return nil }
    context.availableHeight = height
    context.environment.sheetDetentHeight = height
    return height
}
