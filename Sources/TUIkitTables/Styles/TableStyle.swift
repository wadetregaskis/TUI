//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - TableStyle

/// A type that applies a custom appearance to all tables within a view.
///
/// Set it with the ``View/tableStyle(_:)`` modifier:
///
/// ```swift
/// Table(people) {
///     TableColumn("Name", value: \.name)
/// }
/// .tableStyle(.inset)
/// ```
///
/// ## Built-in styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | The platform default — **bordered** in TUIkit, the look a table has always had here. |
/// | ``bordered`` | The table drawn inside a rounded border. |
/// | ``inset`` | No border: the header and rows inset a cell from the table's edges. |
/// | ``surface`` | TUIkit's own, a prototype: `.inset` on a surface of its own, the header a step stronger. |
///
/// Stripes are not a style's: every style stripes every other row, as a macOS
/// `Table` does under each (measured), and `.alternatingRowBackgrounds(_:)`
/// turns them off or on under any style, as in SwiftUI.
///
/// ## Custom styles
///
/// A ``TableStyleConfiguration`` has no public members, as SwiftUI's has none,
/// so a custom style cannot draw the table itself — only compose a built-in
/// style's body with other views:
///
/// ```swift
/// struct Padded: TableStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         InsetTableStyle().makeBody(configuration: configuration)
///             .padding()
///     }
/// }
/// ```
///
/// ## Styles and the render cache
///
/// The built-in styles are `Equatable` for the reason ``FormStyle``'s are:
/// ``View/tableStyle(_:)`` puts the style in the environment, and a value the
/// render cache cannot compare turns memoization off beneath it. A custom style
/// that is not `Equatable` costs render time, never correctness.
///
/// - Note: `Sendable`, where SwiftUI's is main-actor isolated, as TUIkit's
///   other styles are: the environment holds the style, and an environment
///   default has to be one.
public protocol TableStyle: Sendable {
    /// A view that represents the body of a table.
    associatedtype Body: View

    /// Creates a view that represents the body of a table.
    ///
    /// - Parameter configuration: The table's properties.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a table.
    typealias Configuration = TableStyleConfiguration
}

/// The properties of a table.
///
/// You don't create this: a table hands one to its style's
/// ``TableStyle/makeBody(configuration:)``. It has no public members, as
/// SwiftUI's has none; a built-in style's body draws the table from it.
public struct TableStyleConfiguration {
    /// The table, drawn by whichever built-in style's body is handed this.
    let table: AnyView
}

// MARK: - Built-in styles

/// How a built-in style frames a table.
enum _TableChrome: Equatable {
    /// A rounded border around the header and rows.
    case bordered
    /// No border; the header and rows inset a cell from the edges.
    case inset
    /// As ``inset``, on a lifted surface, the header on a stronger one
    /// (``SurfaceTableStyle``).
    case surface
}

extension TableStyle {
    /// How this style frames a table, or `nil` for a custom style — which
    /// draws through ``makeBody(configuration:)`` instead.
    var builtInChrome: _TableChrome? {
        switch self {
        case is AutomaticTableStyle, is BorderedTableStyle: .bordered
        case is InsetTableStyle: .inset
        case is SurfaceTableStyle: .surface
        default: nil
        }
    }

    /// Renders this style's body for `configuration`. Opens the
    /// `any TableStyle` existential so ``makeBody(configuration:)`` can return
    /// its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }

    /// Measures this style's body for `configuration` — the measuring twin of
    /// ``makeBuffer(configuration:context:)``.
    @MainActor
    func measureBody(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(makeBody(configuration: configuration), proposal: proposal, context: context)
    }
}

/// The default table style in the current context: **bordered** in TUIkit.
///
/// `Equatable` for the reason given under ``TableStyle``.
public struct AutomaticTableStyle: TableStyle, Equatable {
    /// The table, drawn in this style.
    public func makeBody(configuration: Configuration) -> some View {
        configuration.table.tableStyle(self)
    }
}

/// The table style that describes the behavior and appearance of a table
/// with its content and selection inset from the table edges: no border, the
/// header and rows a cell in from either side.
///
/// `Equatable` for the reason given under ``TableStyle``.
public struct InsetTableStyle: TableStyle, Equatable {
    /// Creates a default inset table style, with alternating row backgrounds
    /// as `.alternatingRowBackgrounds(_:)` says.
    public init() {}

    /// The table, drawn in this style.
    public func makeBody(configuration: Configuration) -> some View {
        configuration.table.tableStyle(self)
    }
}

/// The table style that describes the behavior and appearance of a table
/// with its content and selection inset from the table edges and surrounded
/// by a border: TUIkit's rounded box.
///
/// `Equatable` for the reason given under ``TableStyle``.
public struct BorderedTableStyle: TableStyle, Equatable {
    /// Creates a default bordered table style, with alternating row
    /// backgrounds as `.alternatingRowBackgrounds(_:)` says.
    public init() {}

    /// The table, drawn in this style.
    public func makeBody(configuration: Configuration) -> some View {
        configuration.table.tableStyle(self)
    }
}

/// TUIkit's own table style, and a PROTOTYPE to try: the table told from the
/// text around it by a surface of its own rather than by a border. The
/// header and rows inset a cell from the edges, as under ``InsetTableStyle``,
/// on the surface a `TabView`'s body is drawn on — one plane's step off what
/// the table sits on — and the header on a step stronger still, its titles
/// bold in the primary ink. Every other row stripes over that surface, as
/// under every style.
///
/// SwiftUI has no such style: a macOS table needs none, its window drawing a
/// table's rows on a field of their own. Whether TUIkit's default should look
/// like this is the owner's open question (decisions A29, and A-D6L-1 in the
/// D6L decisions); the name may change, or go, when it is answered.
///
/// `Equatable` for the reason given under ``TableStyle``.
public struct SurfaceTableStyle: TableStyle, Equatable {
    /// Creates a surface table style.
    public init() {}

    /// The table, drawn in this style.
    public func makeBody(configuration: Configuration) -> some View {
        configuration.table.tableStyle(self)
    }
}

extension TableStyle where Self == AutomaticTableStyle {
    /// The default table style in the current context: bordered in TUIkit.
    public static var automatic: AutomaticTableStyle { AutomaticTableStyle() }
}

extension TableStyle where Self == InsetTableStyle {
    /// The table style that describes the behavior and appearance of a table
    /// with its content and selection inset from the table edges.
    public static var inset: InsetTableStyle { InsetTableStyle() }
}

extension TableStyle where Self == BorderedTableStyle {
    /// The table style that describes the behavior and appearance of a table
    /// with its content and selection inset from the table edges and
    /// surrounded by a border.
    public static var bordered: BorderedTableStyle { BorderedTableStyle() }
}

extension TableStyle where Self == SurfaceTableStyle {
    /// TUIkit's own: an inset table on a surface of its own, the header a step
    /// stronger — a prototype (see ``SurfaceTableStyle``).
    public static var surface: SurfaceTableStyle { SurfaceTableStyle() }
}

// MARK: - Environment

/// Environment key for the table style.
private struct TableStyleKey: EnvironmentKey {
    static let defaultValue: any TableStyle = AutomaticTableStyle()
}

extension EnvironmentValues {
    /// The style ``Table`` views render with. Set via ``View/tableStyle(_:)``.
    /// Default: ``AutomaticTableStyle``.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not
    /// `Equatable` turns memoization off in its subtree — see ``TableStyle``.
    public var tableStyle: any TableStyle {
        get { self[TableStyleKey.self] }
        set { self[TableStyleKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the style for tables within this view.
    ///
    /// ```swift
    /// Table(people) { … }
    ///     .tableStyle(.inset)
    /// ```
    ///
    /// - Parameter style: The table style to apply.
    /// - Returns: A view whose tables use the specified style.
    public func tableStyle<S: TableStyle>(_ style: S) -> some View {
        environment(\.tableStyle, style)
    }
}
