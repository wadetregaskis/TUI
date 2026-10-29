//  🖥️ TUI — A Terminal UI framework for Swift
//  Spacer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A flexible spacer that fills available space.
///
/// `Spacer` expands along the main axis of its container
/// and fills the available space between other views.
///
/// # Example in HStack
///
/// ```swift
/// HStack {
///     Text("Left")
///     Spacer()
///     Text("Right")
/// }
/// // Result: "Left                    Right"
/// ```
///
/// # Example in VStack
///
/// ```swift
/// VStack {
///     Text("Top")
///     Spacer()
///     Text("Bottom")
/// }
/// ```
public struct Spacer: View, Equatable {
    /// The minimum length this spacer can be shrunk to, along the axis or axes
    /// of expansion, in cells.
    ///
    /// If `nil`, the default distance between two views along its stack's
    /// axis: one column in a row, none in a column. SwiftUI's is a `CGFloat?`
    /// of points; a terminal lays out whole cells, as ``init(minLength:)``
    /// takes them.
    public var minLength: Int?

    /// Creates a spacer with optional minimum length.
    ///
    /// - Parameter minLength: The minimum length, in cells. If nil, the
    ///   spacer is never shorter than the default distance between two views
    ///   along its stack's axis — one column in a row, none in a column — as
    ///   SwiftUI's is never shorter than the system spacing (measured: 8
    ///   points). Beside it the stack puts no gap of its own where its
    ///   `spacing` is `nil`, so a row with no room to spare is as wide with a
    ///   spacer as without one.
    public init(minLength: Int? = nil) {
        self.minLength = minLength?.heldToStatedLength
    }

    public var body: Never {
        fatalError("Spacer is a primitive view")
    }

    /// Static witness used by the child-layout path to detect a spacer without a
    /// runtime `as? SpacerProtocol` cast. See ``View/_isSpacer``.
    public static var _isSpacer: Bool { true }

    /// A spacer states a spacing preference: none, on every edge (measured
    /// on SwiftUI: `spacer|box` is 0 apart either way —
    /// `Tools/SwiftUIProbes/Stack spacing per pair/distances.out`).
    public static var _statesSpacingPreference: Bool { true }

    /// The length a spacer with no `minLength` is never shorter than along
    /// `axis`: the distance a stack puts between two views that state no
    /// spacing — one column in a row, none in a column.
    static func defaultMinLength(along axis: Axis) -> Int {
        ViewSpacing().distance(to: ViewSpacing(), along: axis)
    }
}

// MARK: - A Spacer Child's Length

extension ChildView {
    /// A spacer child's length when nothing is spare along `axis`: its
    /// `minLength`, or the default distance between two views along it
    /// (``Spacer/defaultMinLength(along:)``) — one column in a row.
    func spacerLength(along axis: Axis) -> Int {
        spacerMinLength ?? Spacer.defaultMinLength(along: axis)
    }
}

// MARK: - Spacer Protocol Conformance

/// ``minLength`` is the requirement, under SwiftUI's name.
extension Spacer: SpacerProtocol {}

// MARK: - Spacer Rendering

extension Spacer: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Spacer is fully flexible - it expands to fill available space.
        // The minLength is its minimum size requirement; without one, the
        // default distance along the stack's axis (``defaultMinLength(along:)``),
        // which a stack's own spacer path reads from the child instead.
        let axis = context.environment.containerAxis
        let width = minLength ?? (axis == .horizontal ? Self.defaultMinLength(along: .horizontal) : 0)
        let height = minLength ?? (axis == .vertical ? Self.defaultMinLength(along: .vertical) : 0)
        // Natural: the answer is the minimum length and the two fill flags,
        // whatever space was offered in either direction.
        return ViewSize(
            width: width,
            height: height,
            isWidthFlexible: true,
            isHeightFlexible: true
        ).declaringNaturalSize()
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Standalone spacer (outside a stack): render as empty lines
        let count = minLength ?? 1
        return FrameBuffer(emptyWithHeight: count)
    }
}
