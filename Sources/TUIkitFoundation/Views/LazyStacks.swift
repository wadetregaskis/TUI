//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyStacks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - LazyVStack

/// A view that arranges its children in a line that grows vertically,
/// rendering only the children that fit.
///
/// TUIkit re-renders the tree every frame and retains no view objects, so
/// SwiftUI's "create items only as needed" translates here to a **render
/// window**: whole children render top-down until the next would overflow
/// `availableHeight`, and children past the fold are never rendered (their
/// `onAppear`/`task` correctly never fire). `VStack` instead distributes the
/// height and clips at the cell.
///
/// Use `LazyVStack` when the *stack itself* is the clipped region — a
/// fixed-height pane showing "as many whole rows as fit".
///
/// - Important: A `LazyVStack` that is the *direct content* of a vertical
///   ``ScrollView`` now windows to the visible viewport: only the rows
///   intersecting the scrolled slice render (and fire their lifecycle), the
///   rest becoming blank placeholders in a full-height buffer, so scrolling a
///   1000-row list costs a viewport's worth of rendering, not all 1000 — and
///   `onAppear` fires on visibility, matching SwiftUI. (A `LazyVStack` nested
///   *below* other scroll content isn't at the content origin, so it is left
///   un-windowed — and so is one alone inside an outer lazy stack, which takes
///   the window itself. A `Section`'s header and footer are not such content:
///   the section hands its content the window moved below its header, so a
///   lazy stack there windows, seeks and reports its row as it would with
///   neither. Every row of a stack left un-windowed is measured and drawn, as
///   in a `VStack`, so its cost per frame tracks its row count — and in a row
///   of an outer lazy stack it is measured whenever the outer stack places
///   that row, on screen or not.)
///
/// # Pinned section headers and footers
///
/// With `pinnedViews:`, a `Section`'s header stays at the top of the
/// enclosing vertical ``ScrollView`` while any of its section's content is
/// under it, and is pushed up and away by the section's last row — so the
/// next section's header takes over; a pinned footer stays at the bottom the
/// same way, never above its section's first row. That is SwiftUI's rule,
/// measured on macOS 15.8, and it holds wherever the stack sits in the
/// scroll view's content, windowed or not. Under the "N more above / below"
/// indicators (`.scrollIndicatorStyle(.text)`) a pinned header sits below the
/// line rather than under it. A control in a pinned header is clicked where
/// it is drawn, and the rows it covers cannot be; focus moving onto a row
/// scrolls it clear of the pinned header, though `scrollTo(_:anchor:)` puts
/// a row under it, as SwiftUI's does. Only the stack's own
/// sections pin — written in its content or made there by a `ForEach` — and
/// outside a scroll view nothing does. A section of its own is laid out as
/// the stack lays out its children, `spacing` between its header and its
/// first row as between any two rows (SwiftUI's spacing, measured).
///
/// ```swift
/// ScrollView {
///     LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
///         ForEach(groups) { group in
///             Section(group.name) {
///                 ForEach(group.items) { Text($0.title) }
///             }
///         }
///     }
/// }
/// ```
///
/// Two deviations: SwiftUI's header is transparent, so the rows scrolling
/// under it show through wherever it draws nothing. A cell holds one
/// glyph, so here the header's cells replace the rows' glyphs across the
/// section's width, and keep only their background. And to pin them, the
/// stack keeps its own sections whole where any other container takes a
/// section apart — unpinned too, for the sections a `ForEach` makes, so a
/// loop of them stays lazy: a centre-aligned section's views are centred
/// within the section's widest view and the section within the stack, which
/// can be a cell from where the stack would centre the same views taken
/// apart, and a modifier on such a section wraps the section rather than
/// each view.
///
/// - Note: Documented deviations from SwiftUI (per the parity rule): the
///   cross-axis width hugs the widest *placed* child (SwiftUI's ideal width
///   is its **first** subview's — an artefact of not creating the rest;
///   TUIkit has rendered every visible child anyway, so it uses the real
///   widest), and the main-axis extent is exact rather than estimated.
///   "Placed" means the rows a walk at the given height budget reaches; past
///   the fold a windowed stack answers from the widest row it has drawn or
///   sampled, never below the band it is currently drawing. See §2.8 of
///   `Documentation/SwiftUI-compatibility.md`.
///
/// # Example
///
/// ```swift
/// ScrollView {
///     LazyVStack {
///         ForEach(1...1000, id: \.self) { i in
///             Text("Row \(i)")
///         }
///     }
/// }
/// ```
///
/// - Note: `LazyVStack` shares its rendering core (`_VStackCore`) with
///   ``VStack``; the only difference is the `.window` overflow policy, which
///   appends whole children while they fit `availableHeight` and stops at the
///   first that would overflow (rather than `VStack`'s `.clip`, which distributes
///   and clips trailing rows at the cell).
public struct LazyVStack<Content: View>: View {
    /// The horizontal alignment of the children.
    public let alignment: HorizontalAlignment

    /// The vertical spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// The kinds of child views pinned to the enclosing scroll view's edges.
    let pinnedViews: PinnedScrollableViews

    /// Creates a lazy vertical stack with the given spacing, horizontal
    /// alignment, pinning behaviour and content.
    ///
    /// - Parameters:
    ///   - alignment: The horizontal alignment of children (default: .center).
    ///   - spacing: The blank lines between children, or `nil` (the default)
    ///     for what views prefer between them: none.
    ///   - pinnedViews: The kinds of child views that will be pinned to the
    ///     enclosing scroll view's edges: the headers and footers of the
    ///     stack's `Section`s (default: none). See the discussion above.
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .vertical)
        self.content = content()
        self.pinnedViews = pinnedViews
    }

    public var body: some View {
        _VStackCore(
            alignment: alignment, spacing: spacing, overflow: .window, pinnedViews: pinnedViews,
            content: content)
    }
}

// MARK: - LazyHStack

/// A view that arranges its children in a line that grows horizontally,
/// rendering only the children that fit.
///
/// The horizontal render window: whole children render left-to-right until
/// the next would overflow `availableWidth`, and children past the fold are
/// never rendered. `HStack` instead distributes the width and clips at the
/// cell. Use `LazyHStack` when the *stack itself* is the clipped region.
///
/// # Example
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHStack {
///         ForEach(1...1000, id: \.self) { i in
///             Text("Column \(i)")
///         }
///     }
/// }
/// ```
///
/// # Pinned section headers and footers
///
/// A `Section` in a row is laid out along it, as SwiftUI's is: its header at
/// the leading end, its views after it, its footer at the trailing end. With
/// `pinnedViews:`, a section's header stays at the leading edge of the
/// enclosing horizontal ``ScrollView`` while any of its section's content is
/// under it, and is pushed off by the section's last column; a pinned footer
/// stays at the trailing edge the same way — ``LazyVStack``'s rule turned on
/// its side, as SwiftUI's is (measured on macOS 15.8):
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHStack(pinnedViews: [.sectionHeaders, .sectionFooters]) {
///         ForEach(albums) { album in
///             Section {
///                 ForEach(album.photos) { Text($0.caption) }
///             } header: {
///                 Text(album.title)
///             } footer: {
///                 Text("\(album.photos.count)")
///             }
///         }
///     }
/// }
/// ```
///
/// The deviations are ``LazyVStack``'s, on their side: a pinned header's
/// cells replace the columns' glyphs, and the stack keeps its own sections
/// whole to pin them, so a centre-aligned section's views can sit a cell from
/// where the stack would centre them unpinned. Focus moving onto a column does
/// not scroll it clear of a pinned header, as it does in a column.
///
/// - Note: `LazyHStack` is the horizontal twin of ``LazyVStack`` — see its
///   discussion for the render-window semantics, the `ScrollView` caveat, and
///   the documented deviations from SwiftUI.
///
/// - Note: `LazyHStack` shares its rendering core (`_HStackCore`) with
///   ``HStack``; the only difference is the `.window` overflow policy, which
///   appends whole children while they fit `availableWidth` and stops at the
///   first that would overflow (rather than `HStack`'s `.clip`, which distributes
///   and clips trailing columns at the cell).
public struct LazyHStack<Content: View>: View {
    /// The vertical alignment of the children.
    public let alignment: VerticalAlignment

    /// The horizontal spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// The kinds of child views pinned to the enclosing scroll view's edges.
    let pinnedViews: PinnedScrollableViews

    /// Creates a lazy horizontal stack with the given spacing, vertical
    /// alignment, pinning behaviour and content.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment of children (default: .center).
    ///   - spacing: The blank columns between children, or `nil` (the default)
    ///     for what views prefer between them: one column.
    ///   - pinnedViews: The kinds of child views that will be pinned to the
    ///     enclosing horizontal scroll view's leading and trailing edges: the
    ///     headers and footers of the stack's `Section`s (default: none). See
    ///     the discussion above.
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .horizontal)
        self.content = content()
        self.pinnedViews = pinnedViews
    }

    public var body: some View {
        _HStackCore(
            alignment: alignment, spacing: spacing, overflow: .window, pinnedViews: pinnedViews,
            content: content)
    }
}

// MARK: - Equatable Conformances

extension LazyVStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: LazyVStack<Content>, rhs: LazyVStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
            && lhs.pinnedViews == rhs.pinnedViews
    }
}

extension LazyHStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: LazyHStack<Content>, rhs: LazyHStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
            && lhs.pinnedViews == rhs.pinnedViews
    }
}
