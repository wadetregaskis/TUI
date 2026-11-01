//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Layout.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Border

extension View {
    /// Adds a border around this view.
    ///
    /// Content is inset by 1 character on each side so text doesn't touch
    /// the border characters. The total width overhead is 4 characters
    /// (2 for borders + 2 for inner padding). A `TextEditor` is not inset: its
    /// field reaches its edges and keeps the text off the line, and the inset
    /// would be a strip of the page between the two — the border sits on its
    /// edges, as SwiftUI's does on any view's.
    ///
    /// Internally this creates a `ContainerView` without title or footer,
    /// ensuring consistent padding and rendering across all bordered views.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hello")
    ///     .border()               // the appearance's style, the palette's colour
    ///
    /// Text("Warning")
    ///     .border(.red)           // SwiftUI's spelling, and it means the same
    ///
    /// Text("Rounded")
    ///     .border(.cyan, style: .rounded)
    ///
    /// Text("Emphatic")
    ///     .border(.yellow, style: .doubleLine, width: 2)
    /// ```
    ///
    /// The colour comes first and unlabelled because that is where SwiftUI puts
    /// it: `border(_ content: some ShapeStyle, width: CGFloat = 1)`. A terminal
    /// border has something SwiftUI's has not — the box-drawing characters it
    /// is made of — so `style:` is added rather than substituted, and the two
    /// spellings agree on everything they share.
    ///
    /// - Parameters:
    ///   - colour: The border colour.
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: How many concentric rings to draw, in CELLS — a terminal has
    ///     no fractional stroke, so a thicker border is literally a border
    ///     around a border. `0` draws none; values above 1 nest.
    /// - Returns: A view with a border.
    nonisolated public func border(
        _ colour: Color,
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: AnimatedColor(colour), width: width)
    }

    /// A border whose colour breathes, blinks, or otherwise moves.
    ///
    /// The cheap way to show that your own view holds the focus. The border is
    /// drawn here, so it is this modifier — not the caller — that knows which
    /// cells to animate, and it leaves ``AnimatedCellRun``s for them. Nothing
    /// re-renders per tick. A faded colour is blended too, provided every frame is
    /// at one alpha: a replayed run is blended at one alpha per cell, so frames at
    /// different alphas — the example below under `.tint(.red.opacity(0.5))` — show
    /// at full strength. `Color.breathEnds(dimmedTo:over:)` gives two ends at one.
    ///
    /// ```swift
    /// Text("Right-click me")
    ///     .border(emphasis.animatedColor(
    ///         isFocused, dim: palette.border, bright: palette.accent))
    /// ```
    ///
    /// A still ``AnimatedColor`` (an unfocused element, or a
    /// `.selectionIndicatorStyle(.none)`) simply draws its one colour and
    /// leaves nothing behind, so the call site need not branch.
    ///
    /// - Parameters:
    ///   - colour: The border colour, as every frame of its cycle.
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: Concentric rings, in cells. Every ring animates.
    /// - Returns: A view with a border that moves.
    nonisolated public func border(
        _ colour: AnimatedColor,
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: colour, width: width)
    }

    /// A border in the palette's own colour — the terminal-native spelling,
    /// where the theme decides and the call site does not have to.
    ///
    /// SwiftUI has no equivalent because it has no palette: there, a border
    /// with no colour is `border(.foreground)`. Here it is what nearly every
    /// call wants, so it stays available rather than forcing a colour that a
    /// theme change would then have to fight.
    ///
    /// - Parameters:
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: Concentric rings, in cells.
    /// - Returns: A view with a border.
    nonisolated public func border(
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: nil, width: width)
    }

    /// The one implementation both spellings funnel through, and the one the
    /// framework's own chrome calls when its colour is already an `Optional`
    /// (a menu or popover whose caller may or may not have named one).
    ///
    /// `width` nests rather than thickens: each ring is another
    /// `ContainerView` around the last, which is exactly what a two-cell
    /// border looks like on a grid that has no half-cells.
    ///
    /// The rings are erased (an `AnyView` per ring), which is faster than
    /// their nested type spelt out, and handed over as ``_BorderRings``, whose
    /// type says they are one view — so a bordered view counts as one child
    /// from its type, as the view it borders does.
    ///
    /// `keepsSelectionInside` is off for a control's own box — a menu's —
    /// whose presses are the control's (``ContainerConfig/keepsSelectionInside``).
    @ViewBuilder
    nonisolated func bordered(
        style: BorderStyle?, colour: AnimatedColor?, width: Int, keepsSelectionInside: Bool = true
    ) -> some View {
        if width <= 0 {
            self
        } else {
            _BorderRings<Self>(
                rings: (1..<max(1, width)).reduce(
                    ring(style: style, colour: colour, keepsSelectionInside: keepsSelectionInside)
                ) { inner, _ in
                    inner.ring(style: style, colour: colour, keepsSelectionInside: keepsSelectionInside)
                })
        }
    }

    /// One border, drawn as the titleless container it has always been: a
    /// blank cell either side of the content, so text does not run up against
    /// the line — and none for content that paints its own surface to its
    /// edges (``View/_paintsToItsEdges``), whose blank cells were strips of the page
    /// between the border and the surface. That one is SwiftUI's own border,
    /// which is drawn on the view's edge with no inset at all.
    ///
    /// The inset goes beneath a background the content ends in, which then
    /// reaches the line (`BackgroundBeneathBorderInset.swift`).
    nonisolated private func ring(style: BorderStyle?, colour: AnimatedColor?, keepsSelectionInside: Bool) -> AnyView {
        let style = ContainerStyle(
            showHeaderSeparator: false,
            showFooterSeparator: false,
            borderStyle: style,
            borderColor: colour,
            keepsSelectionInside: keepsSelectionInside
        )
        let inset = EdgeInsets(horizontal: 1, vertical: 0)
        if Self._paintsToItsEdges {
            return AnyView(ContainerView(style: style, padding: EdgeInsets()) { self })
        }
        if let backed = self as? any BackgroundBeneathBorderInset {
            return AnyView(ContainerView(style: style, padding: EdgeInsets()) { backed.paddingBeneathBackground(inset) })
        }
        return AnyView(ContainerView(style: style, padding: inset) { self })
    }
}

// MARK: - Border rings

/// A border's rings, erased, under a type that says they are ONE view.
///
/// An `AnyView`'s type cannot say how many views it holds, so it counts as
/// none known (`staticMemberCount` is `nil`): the rings alone were one child
/// of their container at run time — a `ContainerView` — and unknown from
/// their type. `.border()` is an `if`/`else` of the view it borders and its
/// rings, so a row of several views with one of them bordered —
/// `Text("a"); Text("b").border()` — counted as varying where it counted two
/// before an `AnyView` was a provider (a7e0b83e3), and a `ForEach` of such
/// rows built and counted every row on every walk: no row memo, and a lazy
/// stack without its window.
///
/// Not a provider of children, so its type counts one; drawn and measured as
/// the `AnyView` it holds, at the same identity — the rings stay erased,
/// which is faster than their nested type spelt out (an un-erased ring
/// measured +20.5% on the `anyview` scenario). The bordered view's type is
/// kept as a parameter alone, so a guide inside it can be found and reported
/// out through the rings (`WrapperGuidePropagation.swift`).
nonisolated struct _BorderRings<Bordered: View>: View, Renderable, Layoutable {
    let rings: AnyView

    @MainActor var body: Never { fatalError("_BorderRings renders via Renderable") }

    /// The bordered view's answer: the rings hold it, and report its guides
    /// moved in by their lines and padding.
    @MainActor static var _providesAlignmentGuide: Bool { Bordered._providesAlignmentGuide }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        rings.renderToBuffer(context: context)
    }

    @MainActor func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        rings.sizeThatFits(proposal: proposal, context: context)
    }
}

// MARK: - Dimmed

extension View {
    /// Applies a dimming effect to the view content.
    ///
    /// This reduces the visual intensity of the content using the ANSI dim
    /// escape code — a purely visual change.
    ///
    /// Dimmed content is **inert**: what looks recessive is recessive. It is
    /// not a Tab stop, its `onKeyEvent` and `.keyboardShortcut` do not fire, it
    /// publishes no status-bar items, and it is not clickable. Its `@State` and
    /// scroll position survive, so undimming brings it back as it was.
    ///
    /// > Important: inert is still not the same as **modal**. This dims and
    /// > deadens the content it is applied to and nothing else: it does not
    /// > centre a dialog on the screen, capture focus into a section of its
    /// > own, publish ESC to dismiss, or stop a sibling elsewhere in the tree
    /// > from being reached. Present a ``Dialog`` or an ``AlertPanel`` through
    /// > ``View/modal(isPresented:onDismiss:content:)`` or
    /// > ``View/alert(_:isPresented:actions:message:borderStyle:borderColor:titleColor:)-(LocalizedStringKey,_,_,_,_,_,_)``, which do
    /// > all of that; `.dimmed()` is for content you want recessive in place.
    ///
    /// It also **drops** anything the content floated: a presentation, a
    /// `Picker` drop-down or a context menu inside a `.dimmed()` subtree is
    /// discarded, by construction — a backdrop is meant to be flat and inert.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("This content will be dimmed")
    ///     Text("All text is affected")
    /// }
    /// .dimmed()
    /// ```
    ///
    /// - Returns: A view with the dimming effect applied.
    nonisolated public func dimmed() -> some View {
        DimmedModifier(content: self)
    }
}

// MARK: - Background

extension View {
    /// Adds a background to this view — a colour, or any gradient.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Warning!")
    ///     .foregroundStyle(.black)
    ///     .background(.yellow)
    ///
    /// VStack {
    ///     Text("Header")
    /// }
    /// .background(.blue)
    /// ```
    ///
    /// - Parameter style: The background style — a colour, or any gradient.
    /// - Returns: A view with the background applied.
    nonisolated public func background<S: ShapeStyle>(_ style: S) -> some View {
        modifier(BackgroundModifier(style: style))
    }

    /// Fills this view's cells with the background style in force — from
    /// ``View/backgroundStyle(_:)-(S)``, or the palette's own background where
    /// nothing has named one.
    ///
    /// SwiftUI's zero-argument `background()`, minus `ignoresSafeAreaEdges:`:
    /// a terminal has no safe area for an argument to talk about, so the
    /// spelling that means something is the only one that compiles.
    ///
    /// - Returns: A view filled with the environment's background style.
    nonisolated public func background() -> some View {
        background(BackgroundStyle())
    }

    /// The colour spelling, so `.background(.red)` and
    /// `.background(.palette.surface)` keep inferring what they always did —
    /// the same `@_disfavoredOverload` pair `foregroundStyle` uses, and that
    /// Apple ships for `tint`.
    @_disfavoredOverload
    nonisolated public func background(_ color: Color) -> some View {
        modifier(BackgroundModifier(style: color))
    }
}

// MARK: - Frame

extension View {
    /// Sets an explicit frame size for this view.
    ///
    /// The content is aligned within the frame according to the specified alignment.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hello")
    ///     .frame(width: 20, alignment: .center)
    /// ```
    ///
    /// - Parameters:
    ///   - width: The desired width in characters (nil preserves intrinsic width).
    ///   - height: The desired height in lines (nil preserves intrinsic height).
    ///   - alignment: The alignment within the frame (default: .topLeading).
    ///     This **intentionally** differs from SwiftUI's `.center`: a terminal
    ///     reads from the top-left, and a fixed `.frame(width:)` is overwhelmingly
    ///     used to make a left-aligned, fixed-width column (labels, channel
    ///     sliders, table cells), not to centre content in slack space. Centring
    ///     by default would surprise TUI authors and silently shift such columns.
    ///     Pass an explicit `alignment:` when you do want centring.
    /// - Returns: A view constrained to the specified frame.
    nonisolated public func frame(
        width: Int? = nil,
        height: Int? = nil,
        alignment: Alignment = .topLeading
    ) -> some View {
        FlexibleFrameView(
            content: self,
            minWidth: width,
            idealWidth: width,
            maxWidth: width.map { .fixed($0) },
            minHeight: height,
            idealHeight: height,
            maxHeight: height.map { .fixed($0) },
            alignment: alignment
        )
    }

    /// Sets flexible frame constraints for this view.
    ///
    /// The frame is sized as SwiftUI's is. Along each axis it offers its
    /// content what it was offered — or its ideal, when it was offered
    /// nothing, as under ``View/fixedSize(horizontal:vertical:)`` — held to the
    /// maximum. Its own size is the content's, raised to the minimum, and
    /// grown to what it was offered up to the maximum: a frame with a maximum
    /// fills its offer up to it, so `Text("Short").frame(maxWidth: 30)` is 30
    /// cells wide offered 80, and `.infinity` fills whatever it is offered.
    /// An ideal is read only when nothing was offered.
    ///
    /// Offered no width, a frame with an ideal width is exactly that ideal,
    /// its content placed in it by `alignment`: `Text("short").frame(idealWidth:
    /// 10).fixedSize()` is ten wide. One difference from SwiftUI: down the
    /// column a frame with an ideal height and no maximum is its content's
    /// height even offered nothing, where SwiftUI's is the ideal — a stack asks
    /// every child its natural height by offering it none, so that ask cannot
    /// mean SwiftUI's unspecified one here. Add a maximum
    /// (`.frame(idealHeight: 3, maxHeight: .infinity)`) for SwiftUI's size.
    ///
    /// # Examples
    ///
    /// ```swift
    /// // Expand to full width
    /// Text("Hello")
    ///     .frame(maxWidth: .infinity)
    ///
    /// // Expand to full size
    /// Color.blue
    ///     .frame(maxWidth: .infinity, maxHeight: .infinity)
    ///
    /// // Minimum size with expansion
    /// Text("Button")
    ///     .frame(minWidth: 10, maxWidth: .infinity)
    ///
    /// // As wide as offered, up to 60 columns
    /// Text(message)
    ///     .frame(maxWidth: 60, alignment: .leading)
    /// ```
    ///
    /// - Parameters:
    ///   - minWidth: Minimum width in characters.
    ///   - idealWidth: The width offered to the content, and the frame's width,
    ///     when the frame is offered no width.
    ///   - maxWidth: Maximum width, filled up to when offered more, or
    ///     `.infinity` to fill whatever is offered. An integer literal is a
    ///     width in characters.
    ///   - minHeight: Minimum height in lines.
    ///   - idealHeight: The height offered to the content, and the frame's
    ///     height, when the frame is offered no height.
    ///   - maxHeight: Maximum height, filled up to when offered more, or
    ///     `.infinity` to fill whatever is offered.
    ///   - alignment: The alignment within the frame (default: .center).
    /// - Returns: A view with flexible frame constraints.
    nonisolated public func frame(
        minWidth: Int? = nil,
        idealWidth: Int? = nil,
        maxWidth: FrameDimension? = nil,
        minHeight: Int? = nil,
        idealHeight: Int? = nil,
        maxHeight: FrameDimension? = nil,
        alignment: Alignment = .center
    ) -> some View {
        FlexibleFrameView(
            content: self,
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight,
            alignment: alignment
        )
    }
}

// MARK: - Overlay

extension View {
    /// Layers the specified view on top of this view.
    ///
    /// The overlay is positioned according to the specified alignment
    /// within the bounds of the base view.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Background content here")
    ///     .overlay(alignment: .center) {
    ///         Text("Centered overlay")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - alignment: The alignment of the overlay (default: .center).
    ///   - content: The overlay content.
    /// - Returns: A view with the overlay applied.
    nonisolated public func overlay<Overlay: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        OverlayModifier(base: self, overlay: content(), alignment: alignment)
    }
}

// MARK: - Padding

extension View {
    /// Adds padding on all sides.
    ///
    /// In a terminal context, 1 unit of padding means:
    /// - **Vertical (top/bottom):** 1 line
    /// - **Horizontal (leading/trailing):** 1 character
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding(2)   // 2 lines top/bottom, 2 chars left/right
    /// ```
    ///
    /// - Parameter length: The padding amount on all sides.
    /// - Returns: A padded view.
    nonisolated public func padding(_ length: Int) -> some View {
        modifier(PaddingModifier(insets: EdgeInsets(all: length)))
    }

    /// Adds padding on specific edges.
    ///
    /// In a terminal context, 1 unit of padding means:
    /// - **Vertical (top/bottom):** 1 line
    /// - **Horizontal (leading/trailing):** 1 character
    ///
    /// When called without arguments, `.padding()` adds 1 unit on all sides.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding()                // 1 unit on all sides
    ///     .padding(.horizontal, 4)  // 4 chars left and right
    ///     .padding(.vertical, 2)    // 2 lines top and bottom
    /// ```
    ///
    /// - Parameters:
    ///   - edges: The edges to pad (default: `.all`).
    ///   - length: The padding amount (default: 1).
    /// - Returns: A padded view.
    nonisolated public func padding(_ edges: Edge.Set = .all, _ length: Int = 1) -> some View {
        let insets = EdgeInsets(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0
        )
        return modifier(PaddingModifier(insets: insets))
    }

    /// Adds the padding recommended around a scene's root view to the given
    /// edges — mirrors SwiftUI's `scenePadding(_:)`.
    ///
    /// One cell per edge: the ``padding(_:_:)`` default, which is what SwiftUI
    /// documents scene padding as everywhere but watchOS. (macOS measures 20 pt
    /// against `.padding()`'s 16; a cell grid has no size between 1 and 2.)
    ///
    /// - Parameter edges: The edges to pad (default: `.all`).
    /// - Returns: A padded view.
    nonisolated public func scenePadding(_ edges: Edge.Set = .all) -> some View {
        padding(edges)
    }

    /// Adds a kind of scene padding to the given edges — mirrors SwiftUI's
    /// `scenePadding(_:edges:)`.
    ///
    /// - Parameters:
    ///   - padding: The kind of padding: ``ScenePadding/minimum``, one cell.
    ///   - edges: The edges to pad (default: `.all`).
    /// - Returns: A padded view.
    nonisolated public func scenePadding(_ padding: ScenePadding, edges: Edge.Set = .all) -> some View {
        self.padding(edges, padding.length)
    }

    /// Adds padding with explicit edge insets.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
    /// ```
    ///
    /// - Parameter insets: The edge insets.
    /// - Returns: A padded view.
    nonisolated public func padding(_ insets: EdgeInsets) -> some View {
        modifier(PaddingModifier(insets: insets))
    }
}

// MARK: - Scene Padding

/// The kind of padding ``View/scenePadding(_:edges:)`` adds.
public struct ScenePadding: Equatable, Sendable {
    /// The padding, in cells, on each padded edge.
    let length: Int

    /// The minimum scene padding: one cell, the ``View/padding(_:_:)`` default.
    public static let minimum = Self(length: 1)
}
