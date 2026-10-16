//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSize.swift
//
//  SwiftUI's control sizes, read as density: a terminal owns the font and the
//  cell, so a size says how much chrome a control draws around its content.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The size classes, like regular or small, that you can apply to controls
/// within a view — mirrors SwiftUI's `ControlSize`.
///
/// A terminal owns the font and the cell, so a size cannot make a control's
/// text larger. It says how much chrome the control draws around its content:
/// a bordered button at `.small` drops the padding inside its caps, at `.mini`
/// the caps too, and at `.large` and `.extraLarge` it is three rows tall — in
/// a box of lines, or its shape drawn in quadrants on a solid face (see
/// ``ButtonBorderShape`` for the families) — and breathes whole while it holds
/// the focus. The other controls follow where they have chrome to trim or room
/// to give.
///
/// ```swift
/// HStack {
///     Button("Cancel") {}
///     Button("Save") {}
/// }
/// .controlSize(.small)
/// ```
public enum ControlSize: CaseIterable, Sendable, Hashable {
    /// A control version that is minimally sized.
    case mini

    /// A control version that is proportionally smaller size for space-constrained views.
    case small

    /// A control version that is the default size.
    case regular

    /// A control version that is prominently sized.
    case large

    /// A control version that is substantially sized. The largest control
    /// size.
    case extraLarge
}

extension ControlSize: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The size's place in `allCases`, smallest first.
    private var rank: Int {
        switch self {
        case .mini: 0
        case .small: 1
        case .regular: 2
        case .large: 3
        case .extraLarge: 4
        }
    }
}

private struct ControlSizeKey: EnvironmentKey {
    static let defaultValue = ControlSize.regular
}

extension EnvironmentValues {
    /// The size to apply to controls within a view — set with
    /// ``View/controlSize(_:)-(ControlSize)``. The default is `.regular`.
    public var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }
}

extension View {
    /// Sets the size for controls within this view — mirrors SwiftUI's
    /// `controlSize(_:)`.
    ///
    /// - Parameter controlSize: One of the control sizes in ``ControlSize``.
    /// - Returns: A view that sets the size for controls within it.
    public func controlSize(_ controlSize: ControlSize) -> some View {
        environment(\.controlSize, controlSize)
    }

    /// Sets the size for controls within this view to the size in force here,
    /// held within `range` — mirrors SwiftUI's `controlSize(_:)` that takes a
    /// range.
    ///
    /// A size below the range becomes its smallest, one above it its largest,
    /// and one inside it is kept:
    ///
    /// ```swift
    /// Form { … }
    ///     .controlSize(.small ... .large)
    /// ```
    ///
    /// - Parameter range: The sizes the controls within this view may take.
    /// - Returns: A view that holds the size for controls within it in
    ///   `range`.
    public func controlSize<T: RangeExpression>(_ range: T) -> some View where T.Bound == ControlSize {
        transformEnvironment(\.controlSize) { size in
            size = ControlSize.clamping(size, to: range)
        }
    }
}

extension ControlSize {
    /// `size`, held within `range`: kept inside it, the nearest end outside
    /// it, and kept when the range holds no size at all.
    static func clamping<T: RangeExpression>(_ size: Self, to range: T) -> Self where T.Bound == Self {
        let allowed = allCases.filter { range.contains($0) }
        guard let smallest = allowed.first, let largest = allowed.last else { return size }
        return min(max(size, smallest), largest)
    }
}
