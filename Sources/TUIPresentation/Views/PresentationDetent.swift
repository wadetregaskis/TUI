//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationDetent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - PresentationDetent

/// A height a presented sheet can rest at. Matches SwiftUI's type of the same
/// name.
///
/// ```swift
/// .sheet(isPresented: $showing) {
///     DetailView()
///         .presentationDetents([.medium])
/// }
/// ```
///
/// > Note: SwiftUI's `.height(_:)` and `.fraction(_:)` take `CGFloat`; a
///   terminal measures in whole cells, so `.height(_:)` takes `Int` rows. The
///   fraction stays `Double` — it is multiplied by an extent and floored, which
///   is the one place fractional values belong (see the layout parity rule).
///   A ``CustomPresentationDetent`` answers in rows for the same reason.
///
/// A struct with static members, as SwiftUI's is, rather than an enum: a
/// custom detent is a type of the app's own, which no closed list of cases
/// could name.
public struct PresentationDetent: Hashable, Sendable {
    /// What the detent is.
    private enum Kind: Hashable, Sendable {
        case medium
        case large
        case fraction(Double)
        case height(Int)
        case custom(CustomDetent)
    }

    private let kind: Kind

    /// Roughly half the available height.
    public static let medium = Self(kind: .medium)

    /// The full available height.
    public static let large = Self(kind: .large)

    /// A fraction of the available height.
    ///
    /// - Parameter fraction: The fraction of the available height, from 0 to 1.
    public static func fraction(_ fraction: Double) -> Self {
        Self(kind: .fraction(fraction))
    }

    /// An exact number of rows.
    ///
    /// - Parameter height: The height, in rows.
    public static func height(_ height: Int) -> Self {
        Self(kind: .height(height))
    }

    /// A detent whose height a type of the app's own decides. Mirrors
    /// SwiftUI's `custom(_:)`.
    ///
    /// - Parameter type: The type that answers the height.
    public static func custom<D: CustomPresentationDetent>(_ type: D.Type) -> Self {
        Self(kind: .custom(CustomDetent(type)))
    }

    /// This detent's height within `extent` rows, clamped to it — or `nil` for
    /// a custom detent that is not available in `environment`.
    ///
    /// Flooring the fraction rather than rounding is deliberate: a detent that
    /// rounded up could ask for one row more than the screen has, and the
    /// arithmetic that follows would have to defend against it.
    func resolved(in extent: Int, environment: EnvironmentValues = EnvironmentValues()) -> Int? {
        let raw: Int
        switch kind {
        case .medium: raw = extent / 2
        case .large: raw = extent
        case .fraction(let fraction): raw = Int((Double(extent) * fraction).rounded(.down))
        case .height(let rows): raw = rows
        case .custom(let custom):
            guard let rows = custom.height(Context(maxDetentValue: extent, environment: environment)) else {
                return nil
            }
            raw = rows
        }
        return max(1, min(extent, raw))
    }

    /// Whether this detent stands for a height before `other`, when the two
    /// resolve to the same one: `.large`, then `.medium`, then fractions and
    /// heights, larger first, then custom detents by their type's name. An
    /// order, any fixed one, so the detent a sheet's step writes to its
    /// selection does not hang on a `Set`'s order.
    func precedes(_ other: Self) -> Bool {
        func rank(_ kind: Kind) -> (Int, Double, String) {
            switch kind {
            case .large: (0, 0, "")
            case .medium: (1, 0, "")
            case .fraction(let fraction): (2, -fraction, "")
            case .height(let rows): (3, -Double(rows), "")
            case .custom(let custom): (4, 0, custom.name)
            }
        }
        return rank(kind) < rank(other.kind)
    }

    /// What a ``CustomPresentationDetent`` is given to decide its height.
    /// Mirrors SwiftUI's `PresentationDetent.Context`.
    ///
    /// Any environment value can be read from it, as from the environment
    /// itself: `context.dynamicTypeSize`, `context.verticalSizeClass`.
    @dynamicMemberLookup
    public struct Context {
        /// The largest height a detent can be, in rows: the content area's.
        public let maxDetentValue: Int

        /// The environment the sheet is presented in.
        let environment: EnvironmentValues

        /// The environment value at `keyPath`.
        public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
            environment[keyPath: keyPath]
        }
    }

    /// A custom detent: its type, which is what two of them are compared by,
    /// and the type's answer.
    ///
    /// The closure is a call of the type's static requirement and holds nothing
    /// else: a metatype that ``CustomPresentationDetent`` makes `Sendable`.
    private struct CustomDetent: Hashable, Sendable {
        let type: ObjectIdentifier
        let height: @Sendable (Context) -> Int?
        /// The type's name, which orders two custom detents (``precedes(_:)``).
        let name: String

        init<D: CustomPresentationDetent>(_ type: D.Type) {
            self.type = ObjectIdentifier(type)
            height = { D.height(in: $0) }
            name = String(reflecting: type)
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.type == rhs.type }

        func hash(into hasher: inout Hasher) { hasher.combine(type) }
    }
}

// MARK: - CustomPresentationDetent

/// The definition of a custom detent with a calculated height. Mirrors
/// SwiftUI's `CustomPresentationDetent`.
///
/// ```swift
/// struct BarDetent: CustomPresentationDetent {
///     static func height(in context: Context) -> Int? {
///         max(5, context.maxDetentValue / 4)
///     }
/// }
///
/// .presentationDetents([.custom(BarDetent.self), .large])
/// ```
public protocol CustomPresentationDetent: SendableMetatype {
    /// The context a custom detent's height is decided in.
    typealias Context = PresentationDetent.Context

    /// The detent's height, in rows, or `nil` when the detent should not be
    /// available.
    ///
    /// SwiftUI answers in points (`CGFloat`); a terminal answers in rows, as
    /// ``PresentationDetent/height(_:)`` does. The answer is clamped to the
    /// content area and to at least one row.
    static func height(in context: Context) -> Int?
}

// MARK: - Reading the detents

/// A view that carries presentation detents to whatever is presenting it.
///
/// Read by a static conformance check rather than a preference, for the reason
/// the navigation bar's height is a constant: a preference is only readable
/// *after* the subtree renders, and the detent has to be known *before* it, to
/// be the height it renders into. It is found through any other presentation
/// trait applied around it — see ``presentationTrait(_:of:)``.
@MainActor
protocol PresentationDetentsProviding {
    /// The detents this content offers.
    var detents: Set<PresentationDetent> { get }

    /// The detent currently chosen, if the caller bound one.
    var detentSelection: Binding<PresentationDetent>? { get }
}

extension PresentationDetentsProviding {
    /// The heights the sheet can rest at in `extent` rows: each DISTINCT
    /// height once, smallest first, with the detent that names it.
    ///
    /// Distinct, because a short terminal floors detents together — `.medium`
    /// and `.height(5)` are both 5 rows of a 10-row content area — and a step
    /// between two detents of one height would move nothing. Of detents that
    /// collide, one stands for the height by a fixed order (``PresentationDetent/precedes(_:)``),
    /// so which one a step writes to the selection does not depend on a
    /// `Set`'s order.
    ///
    /// A custom detent that answers `nil` is not available, and has no stop.
    func stops(in extent: Int, environment: EnvironmentValues) -> [SheetDetentStop] {
        var byHeight: [Int: PresentationDetent] = [:]
        for detent in detents {
            guard let height = detent.resolved(in: extent, environment: environment) else { continue }
            if let held = byHeight[height], held.precedes(detent) { continue }
            byHeight[height] = detent
        }
        return byHeight.sorted { $0.key < $1.key }.map { SheetDetentStop(height: $0.key, detent: $0.value) }
    }

    /// Where among `stops` the sheet rests: at the height of the detent the
    /// selection binding names, else of the one the sheet keeps for itself
    /// (`chosen`, when nothing binds it), else the SMALLEST — SwiftUI's own
    /// initial state. A named detent that is not offered, or not available,
    /// is passed over the same way.
    func restingIndex(
        among stops: [SheetDetentStop], chosen: PresentationDetent?, extent: Int, environment: EnvironmentValues
    ) -> Int? {
        guard !stops.isEmpty else { return nil }
        let named = detentSelection?.wrappedValue ?? chosen
        if let named, detents.contains(named), let height = named.resolved(in: extent, environment: environment),
            let index = stops.firstIndex(where: { $0.height == height })
        {
            return index
        }
        return 0
    }

    /// The height to present at, in `extent` rows: the resting stop's (see
    /// ``restingIndex(among:chosen:extent:environment:)``), or `nil` when no
    /// detent is available.
    func resolvedHeight(
        in extent: Int, environment: EnvironmentValues, chosen: PresentationDetent? = nil
    ) -> Int? {
        let stops = stops(in: extent, environment: environment)
        return restingIndex(among: stops, chosen: chosen, extent: extent, environment: environment)
            .map { stops[$0].height }
    }
}

/// A presented sheet's detents this frame: the heights it can rest at, and the
/// one it rests at.
///
/// Not main-actor isolated, as the content's detents are: the grabber steps
/// it at event time, from a focus handler (`_SheetGrabberHandler`).
struct PresentedDetents {
    /// The content's selection binding, if it bound one.
    let selection: Binding<PresentationDetent>?
    /// Its distinct heights, smallest first.
    let stops: [SheetDetentStop]
    /// The one it rests at, or `nil` when no detent is available.
    private(set) var index: Int?
    /// Where the sheet keeps a detent the reader chose, when nothing binds it.
    let state: SheetDetentState

    /// The height the sheet rests at, or `nil` when no detent is available
    /// and the sheet is its content's height.
    var height: Int? { index.map { stops[$0].height } }

    /// The detents `content` names, for a sheet presented in `extent` rows —
    /// or `nil` when it names none.
    @MainActor
    init?(of content: any View, extent: Int, environment: EnvironmentValues, state: SheetDetentState) {
        guard let provider = presentationTrait(PresentationDetentsProviding.self, of: content) else { return nil }
        selection = provider.detentSelection
        self.state = state
        stops = provider.stops(in: extent, environment: environment)
        index = provider.restingIndex(among: stops, chosen: state.chosen, extent: extent, environment: environment)
    }

    /// Moves the sheet to stop `target`: through the selection binding when
    /// there is one, as SwiftUI's drag writes it, else into the sheet's own
    /// ``state``. Nothing is written for the stop it already rests at.
    mutating func select(_ target: Int) {
        guard stops.indices.contains(target), target != index else { return }
        index = target
        let detent = stops[target].detent
        if let selection {
            selection.wrappedValue = detent
        } else {
            state.chosen = detent
        }
    }

    /// The stop whose height is nearest `height`, the one it rests at
    /// winning a tie — where a pointer dragging the grabber to `height` rows
    /// snaps the sheet.
    func nearestIndex(toHeight height: Int) -> Int? {
        guard let index else { return nil }
        return stops.indices.min { lhs, rhs in
            let (left, right) = (abs(stops[lhs].height - height), abs(stops[rhs].height - height))
            return left != right ? left < right : lhs == index
        }
    }
}

/// One height a detented sheet can rest at, and the detent that names it —
/// see ``PresentationDetentsProviding/stops(in:environment:)``.
struct SheetDetentStop: Equatable {
    let height: Int
    let detent: PresentationDetent
}

/// The detent a sheet with no selection binding rests at, kept by its
/// presenter for as long as the sheet stays up: `nil` until the reader moves
/// it, and again once it is dismissed or presented for another item
/// (`ModalPresentationModifier.startOver(context:)`), so it opens at the
/// smallest.
///
/// A class, changed in place, as ``KeptSheetSize`` is: the sheet draws at the
/// detent it records on the frame it records it. Not main-actor isolated, for
/// the reason ``PresentedDetents`` is not.
final class SheetDetentState {
    var chosen: PresentationDetent?
}

/// The wrapper `.presentationDetents(_:)` produces. Renders and measures as its
/// content; carrying the detents is its whole job.
struct _PresentationDetentsView<Content: View>: View, PresentationDetentsProviding {
    let content: Content
    let detents: Set<PresentationDetent>
    let detentSelection: Binding<PresentationDetent>?

    var body: Never {
        fatalError("_PresentationDetentsView renders via Renderable")
    }
}

extension _PresentationDetentsView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context)
    }
}

extension _PresentationDetentsView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationDetentsView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

// MARK: - Modifier

extension View {
    /// Sets the available detents for the enclosing sheet. Matches SwiftUI's
    /// signature.
    ///
    /// Apply it to the sheet's **content**, as its outermost modifier:
    ///
    /// ```swift
    /// .sheet(isPresented: $showing) {
    ///     Settings()
    ///         .presentationDetents([.medium])
    /// }
    /// ```
    ///
    /// With more than one, the sheet opens at the smallest and draws a
    /// grabber on its top edge, which the reader drags — or moves with the
    /// keys — between them (see ``presentationDragIndicator(_:)``).
    ///
    /// - Parameter detents: The heights the sheet may rest at.
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        _PresentationDetentsView(content: self, detents: detents, detentSelection: nil)
    }

    /// Sets the available detents and binds the one in use. Matches SwiftUI's
    /// signature.
    ///
    /// The binding is the detent the sheet rests at: the grabber writes it as
    /// the reader moves the sheet, and setting it moves the sheet.
    ///
    /// - Parameters:
    ///   - detents: The heights the sheet may rest at.
    ///   - selection: The detent currently in use.
    public func presentationDetents(
        _ detents: Set<PresentationDetent>,
        selection: Binding<PresentationDetent>
    ) -> some View {
        _PresentationDetentsView(content: self, detents: detents, detentSelection: selection)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationDetentsView: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationDetentsView: DrawsContentUnchanged {}
