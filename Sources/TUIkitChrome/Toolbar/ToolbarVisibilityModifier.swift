//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarVisibilityModifier.swift
//
//  The bar modifiers: a view's say in how the window's bars are drawn —
//  `.toolbarVisibility(_:for:)`, whether a bar is shown, and
//  `.toolbarBackground(_:for:)` / `.toolbarBackgroundVisibility(_:for:)`, what
//  it is filled with.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Public Modifiers

extension View {
    /// Specifies the visibility of a bar managed by the window — mirrors
    /// SwiftUI's `toolbarVisibility(_:for:)`.
    ///
    /// The preferred visibility flows up to the window, as it does on macOS:
    /// ``Visibility/hidden`` takes the bar away — its items, and the rows they
    /// held, a frame later, as any change to the window's bars is adopted —
    /// and ``Visibility/visible`` or ``Visibility/automatic`` leave it to
    /// what is placed in it (a bar with nothing in it is not drawn either way).
    /// When several views state one, the one declared last — the one closest
    /// to the content it wraps — wins.
    ///
    /// ```swift
    /// ContentView()
    ///     .toolbarVisibility(.hidden, for: .bottomBar)
    /// ```
    ///
    /// Hiding the bottom bar hides the line of key hints a `StatusBar()` there
    /// draws, not the keys: they still work. A hidden bar's items keep their
    /// `@State`, so the bar comes back as it went.
    ///
    /// In presented content it states nothing about the window's bars, which
    /// are not its to hide: a sheet that hid the bottom bar took away the line
    /// of key hints that says how to close it. In a sheet or a full-screen
    /// cover it is the presentation's, for the rows it hosts its toolbar's
    /// items in: ``ToolbarPlacement/bottomBar`` its button row,
    /// ``ToolbarPlacement/windowToolbar`` (or ``ToolbarPlacement/automatic``)
    /// its top row.
    ///
    /// - Parameters:
    ///   - visibility: The preferred visibility of the bar.
    ///   - bars: The bars to update: ``ToolbarPlacement/windowToolbar`` (or
    ///     ``ToolbarPlacement/automatic``, or none at all) for the top bar's own
    ///     row, ``ToolbarPlacement/bottomBar`` for the bottom bar, and
    ///     ``ToolbarPlacement/accessoryBar(id:)`` for one of the top bar's
    ///     accessory bars, which hiding the top bar's own row leaves.
    /// - Returns: A view whose bars' preferred visibility is `visibility`.
    public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        _ToolbarBarStatementModifier(content: self, statement: .visibility(visibility), bars: bars)
    }

    /// Specifies the preferred shape style of the background of a bar managed
    /// by the window — mirrors SwiftUI's `toolbarBackground(_:for:)`.
    ///
    /// The style fills the bar in place of the palette's surface for it
    /// (``Palette/appHeaderBackground`` for the top bar,
    /// ``Palette/statusBarBackground`` for the bottom one): every cell of the
    /// bar its items leave bare, its frame's included. A colour, a gradient
    /// (laid across the bar, frame and all) or a ``Material`` (blended over
    /// the page, as a translucent fill is) all work.
    ///
    /// ```swift
    /// ContentView()
    ///     .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
    ///     .toolbarBackground(.blue, for: .bottomBar)
    /// ```
    ///
    /// The preferred style flows up to the window, as visibility does: the one
    /// declared closest to the content wins, and presented content states
    /// nothing. Unlike a bar's presence, the fill is this frame's: it costs no
    /// rows, so nothing waits for the next frame.
    ///
    /// - Parameters:
    ///   - style: The style to display as the background of the bar.
    ///   - bars: The bars to use the style for: ``ToolbarPlacement/windowToolbar``
    ///     (or ``ToolbarPlacement/automatic``, or none at all) for the top bar,
    ///     ``ToolbarPlacement/bottomBar`` for the bottom one, and
    ///     ``ToolbarPlacement/accessoryBar(id:)`` for an accessory bar's row,
    ///     which is otherwise drawn on the top bar's fill.
    /// - Returns: A view whose bars' preferred background is `style`.
    public func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> some View {
        _ToolbarBarStatementModifier(content: self, statement: .background(AnyShapeStyle(style)), bars: bars)
    }

    /// Specifies the preferred visibility of backgrounds on a bar managed by
    /// the window — mirrors SwiftUI's `toolbarBackgroundVisibility(_:for:)`.
    ///
    /// ``Visibility/hidden`` draws the bar with no fill of its own: its items
    /// and frame over the page's background. ``Visibility/visible`` and
    /// ``Visibility/automatic`` fill it — with a `.toolbarBackground(_:for:)`
    /// style if one is stated, else the palette's surface for the bar. A
    /// terminal has no scrolled-under state for `.automatic` to follow, so it
    /// is always filled.
    ///
    /// ```swift
    /// ContentView()
    ///     .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    /// ```
    ///
    /// - Parameters:
    ///   - visibility: The preferred visibility of the background of the bar.
    ///   - bars: The bars to update, as for ``toolbarBackground(_:for:)``.
    /// - Returns: A view whose bars' fill is shown or not as `visibility` says.
    public func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        _ToolbarBarStatementModifier(content: self, statement: .backgroundVisibility(visibility), bars: bars)
    }
}

// MARK: - The Statements

/// What a bar modifier says about the bars it names.
enum _ToolbarBarStatement {
    /// `.toolbarVisibility(_:for:)`: whether the bar is shown.
    case visibility(Visibility)
    /// `.toolbarBackground(_:for:)`: what the bar is filled with.
    case background(AnyShapeStyle)
    /// `.toolbarBackgroundVisibility(_:for:)`: whether the bar is filled.
    case backgroundVisibility(Visibility)
    /// `.toolbarRole(_:)`: where the top bar puts the title.
    case role(ToolbarRole)

    /// Records the statement for `bar`.
    func declare(into chrome: WindowChromeState, for bar: WindowChromeState.BarKey) {
        switch self {
        case .visibility(let visibility): chrome.declare(visibility, for: bar)
        case .background(let style): chrome.declareBackground(style, for: bar)
        case .backgroundVisibility(let visibility): chrome.declareBackgroundVisibility(visibility, for: bar)
        case .role(let role): chrome.declareTitleBesidePrincipal(role.keepsTitleBesidePrincipal)
        }
    }
}

/// Read by a `switch`, as `TrackStyle` is: a payload enum, which the value
/// hash cannot read as bytes, so every view holding a statement — every
/// `.toolbarVisibility(_:for:)`, and every container around one — went
/// unhashed, and unmemoised, where the visibility alone, a one-byte enum, had
/// been read whole. See `_ValueHashing`.
extension _ToolbarBarStatement: _ValueHashing {
    static func _mixValueHash(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .visibility(let visibility): plans.mixCase(0, visibility, into: &hash)
        case .background(let style): plans.mixCase(1, style, into: &hash)
        case .backgroundVisibility(let visibility): plans.mixCase(2, visibility, into: &hash)
        case .role(let role): plans.mixCase(3, role, into: &hash)
        }
    }
}

// MARK: - The Modifier

/// Declares a statement about the window's bars into its chrome as `content`
/// renders — on the drawn walk, and on the first frame's seeding walk, as
/// `.toolbar` declares its items.
struct _ToolbarBarStatementModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let statement: _ToolbarBarStatement
    let bars: [ToolbarPlacement]

    var body: Never { fatalError("_ToolbarBarStatementModifier renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // In a sheet or a cover, a visibility is the presentation's, for the
        // rows it hosts its toolbar's items in (`PresentationToolbarItems`).
        if !context.isMeasuring || context.environment.presentationToolbar?.isSeeding == true {
            declareToPresentation(context: context)
        }
        // Not from presented content: a sheet's toolbar is the sheet's
        // (`ToolbarPresentationRows.swift`), and a sheet hiding the window's
        // bottom bar took the line of key hints that says how to close it.
        if !context.environment.presentationHostsToolbar,
            let chrome = context.environment.windowChrome,
            !context.isMeasuring || context.environment.seedsWindowChrome
        {
            // Declared afresh by every walk: a memoised ancestor serving its
            // buffer would leave the window without the statement.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            for bar in bars.isEmpty ? [.automatic] : bars {
                statement.declare(into: chrome, for: bar.bar)
            }
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    /// The statement is the window's, so this measures as `content` — but for
    /// a presentation's first frame, whose seed finds its rows by a measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if context.environment.presentationToolbar?.isSeeding == true { declareToPresentation(context: context) }
        return measureChild(content, proposal: proposal, context: context)
    }

    /// Records a visibility for the rows of the sheet or cover this content is
    /// presented in: the top row for the window toolbar's placements, the
    /// button row for the bottom bar's. Nothing else a bar modifier says
    /// reaches them.
    private func declareToPresentation(context: RenderContext) {
        guard let host = context.environment.presentationToolbar, case .visibility(let visibility) = statement
        else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        for bar in bars.isEmpty ? [.automatic] : bars {
            switch bar.edge {
            case .bottom: host.declare(visibility, for: .bottom)
            case .automatic, .top: host.declare(visibility, for: .top)
            case .accessory: break
            }
        }
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a z-index or a container value (a `.tag`) written
/// inside it still reaches the container around it — see `_ToolbarModifier`'s
/// conformance. Read-only: not ``ContentRewrapping``.
extension _ToolbarBarStatementModifier: SingleContentWrapper {
    /// Its content's geometry is its own — its statement is the window's, and its content is drawn as it is — so a guide
    /// inside it passes unmoved (``SingleContentWrapper/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    var wrappedContent: Content { content }
}
