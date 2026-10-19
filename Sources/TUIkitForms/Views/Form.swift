//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Form.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Form

/// A container that lays out labelled controls in a consistent, aligned form.
///
/// Mirrors SwiftUI's `Form`. Choose the layout with ``View/formStyle(_:)``:
///
/// - ``FormStyle/columns`` (and ``FormStyle/automatic``, the default) — the
///   classic macOS layout: field labels right-aligned to a shared pillar, controls
///   left-aligned in the column after it, push buttons right-aligned, section
///   headers bold and right-aligned to the pillar, sections separated by a blank
///   line.
/// - ``FormStyle/grouped`` — each ``Section`` drawn as a bordered group, and
///   each field row spread across it as SwiftUI's are: the label at the leading
///   edge, a fixed value at the trailing edge, a field or a slider from 45% of
///   the row, and a toggle's checkbox at the trailing edge, its label leading.
///
/// Row kinds follow macOS conventions:
///
/// - **Field rows** — `LabeledContent("Name") { TextField(…) }` (also `Picker`,
///   `Slider`, `Stepper`, value rows): a right-aligned field label, then the control.
/// - **Checkboxes / radios** — a `Toggle("Wi-Fi", isOn:)` or `RadioButtonGroup`
///   used directly (with its own label) sits in the control column, box first,
///   and the **whole control (box, gap, and label) is clickable** — so don't wrap
///   it in `LabeledContent` unless you want a separate field label to its left.
///   In a grouped form a `Toggle`'s label leads the row and its checkbox trails
///   it, as SwiftUI's does; there the box takes the click.
/// - **Buttons** — a `Button` is right-aligned (macOS places confirmation buttons
///   on the right).
///
/// ```swift
/// Form {
///     Section("Profile") {
///         LabeledContent("Name") { TextField("", text: $name) }
///     }
///     Section("Notifications") {
///         Toggle("Push", isOn: $push)          // box-first, fully clickable
///         Button("Sign Out", role: .destructive) {}   // right-aligned
///     }
/// }
/// ```
public struct Form<Content: View>: View {
    let content: Content

    /// Creates a form with the given content.
    ///
    /// - Parameter content: A view builder producing the form's rows/sections.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        _FormLayout(content: content)
            .paintingScrollContentBackground()
    }
}

// MARK: - Form Row Model

/// One form row, by kind — each laid out per macOS form conventions.
enum _FormRowKind {
    /// A field: right-aligned pillar label + a control/value left-aligned after it.
    case field(label: AnyView, content: AnyView)
    /// A self-labelled control (checkbox/radio): box-first, in the control column,
    /// with its own (clickable) label — or in a grouped form, where it has a
    /// label to move (`parts`), its label leading and the control trailing.
    case control(AnyView, parts: (label: AnyView, control: AnyView)?)
    /// A push button: right-aligned to the form's content width.
    case button(AnyView)
    /// Anything else: a full-width row.
    case plain(AnyView)
}

/// A form row: its kind plus an optional explicit horizontal alignment from
/// ``View/formRowAlignment(_:)``, which overrides the kind's default
/// (e.g. a button's right-alignment).
struct _FormRow {
    var kind: _FormRowKind
    var alignment: HorizontalAlignment?
    /// The modifiers written on the row, put back around the row the form
    /// lays out — a `LabeledContent("Name") { … }.foregroundStyle(.red)` is a
    /// labelled row, red, as SwiftUI's form keeps it (see
    /// `formElements(from:in:)`); `nil` for a row written bare.
    var rewrap: (@MainActor (AnyView) -> AnyView)?
    /// The cells the modifiers written on the row put before it — a leading
    /// padding — which a field row's label needs ahead of it in the label
    /// column: SwiftUI's form widens the column by them, the label staying in
    /// it (measured). Zero for a row written bare.
    var leadingInset = 0
    /// Whether the row's label is hidden by a `.labelsHidden()` written on the
    /// row: a field row then draws no label and takes no part in the label
    /// column, its value staying in the value column, as SwiftUI's form lays
    /// it out (measured). A form whose labels are all hidden has no label
    /// column at all (``_FormLayout``'s pillar).
    var hidesLabel = false

    init(_ kind: _FormRowKind, alignment: HorizontalAlignment? = nil) {
        self.kind = kind
        self.alignment = alignment
    }
}

/// A grouped run of rows with an optional header/footer (from a ``Section``).
///
/// Its rows are elements so that an `if` among them keeps its place
/// (``_FormElement/group(_:branch:)``); a section nested in its content has
/// been flattened into its rows, so none of them is a section.
struct _FormSection {
    var header: AnyView?
    var footer: AnyView?
    var rows: [_FormElement]
    /// Whether the section is drawn open: `false` for a collapsible section
    /// that is collapsed, which draws its header (behind its disclosure
    /// triangle) and nothing else — no rows, and in a grouped form no box.
    var isOpen = true
}

/// A form row paired with its position, for iterating display-only rows
/// without the `ForEach(0..<count)` captured-data memo trap.
///
/// `ForEach(0..<count) { view(rows[index]) }` keys its per-row value memo on
/// the Int index while reading the row content from the captured array — so a
/// changed row served the frozen buffer built at that index the first time
/// (the documented hole `_MemoizedRow` warns framework views away from). This
/// wrapper is deliberately NOT Equatable, so the memo declines to wrap the
/// row at all: a Form rebuilds its rows from `content` every render pass, and
/// display-only rows want exactly that. Identity is positional, stable across
/// frames.
private struct _IndexedFormRow<Value>: Identifiable {
    let id: Int
    let value: Value
}

private func _indexed<Value>(_ items: [Value]) -> [_IndexedFormRow<Value>] {
    items.enumerated().map { _IndexedFormRow(id: $0.offset, value: $0.element) }
}

/// A form element: a bare row, a section of rows, or the elements an `if` or
/// an `if`/`else` holds.
enum _FormElement {
    case row(_FormRow)
    case section(_FormSection)
    /// The elements of an `if` (none while its condition is false) or of one
    /// arm of an `if`/`else`, drawn in ONE place among the form's elements, so
    /// the ones after it keep theirs — a form's rows are identified by
    /// position — and drawn under `branch`, so the two arms of an `if`/`else`
    /// keep their state apart, as their views do anywhere else.
    case group([Self], branch: String?)
}

/// A control a ``Form`` right-aligns (a push button). Conformed by ``Button``.
protocol FormButtonRow {}
extension Button: FormButtonRow {}

// MARK: - Per-row alignment override

extension View {
    /// Overrides a row's horizontal alignment within a ``Form``'s **columns**
    /// layout, taking precedence over the kind's default (e.g. left-align a
    /// `Button` that would otherwise be right-aligned). Outside a columns form it
    /// has no effect.
    ///
    /// ```swift
    /// Form {
    ///     Button("Reset") { … }.formRowAlignment(.leading)  // not right-aligned
    /// }
    /// ```
    ///
    /// - Parameter alignment: The horizontal alignment for the row within the
    ///   form's content width.
    /// - Returns: A view whose form row uses the given alignment.
    public func formRowAlignment(_ alignment: HorizontalAlignment) -> some View {
        _FormRowAlignmentModifier(content: self, alignment: alignment)
    }
}

/// Carries a ``View/formRowAlignment(_:)`` override; transparent
/// outside a form (it just renders its content).
struct _FormRowAlignmentModifier<Content: View>: View {
    let content: Content
    let alignment: HorizontalAlignment
    var body: some View { content }
}

/// A view carrying a per-row alignment override the form applies during extraction.
@MainActor
protocol FormRowAligning {
    var formRowAlignmentValue: HorizontalAlignment { get }
    /// The elements of the view this override is on, read where the form's
    /// walk is (`walk` — see ``formElements(from:in:)``).
    func formRowInnerElements(in walk: RenderContext) -> [_FormElement]
}

extension _FormRowAlignmentModifier: FormRowAligning {
    var formRowAlignmentValue: HorizontalAlignment { alignment }
    func formRowInnerElements(in walk: RenderContext) -> [_FormElement] { formElements(from: content, in: walk) }
}

// MARK: - Row view builder

/// Where the control column begins: one cell past the label pillar (the ~6pt
/// label/control gap), or column 0 when there are no field labels.
private func controlIndent(pillar: Int) -> Int { pillar == 0 ? 0 : pillar + 1 }

/// One row's natural per-kind layout, before any explicit alignment override:
/// a field puts a right-aligned label in the pillar then its content; a
/// checkbox/radio control is indented to the control column; a button and a plain
/// row render at their natural width.
@MainActor @ViewBuilder
private func baseRowView(_ row: _FormRow, pillar: Int) -> some View {
    switch row.kind {
    case .field(let label, let content):
        _FormFieldRow(
            label: label, content: content, pillar: pillar, leadingInset: row.leadingInset,
            hidesLabel: row.hidesLabel)
    case .control(let view, let parts):
        _FormControlRowView(view: view, parts: parts, indent: controlIndent(pillar: pillar))
    case .button(let view):
        view
    case .plain(let view):
        view
    }
}

/// A self-labelled control's row: in the control column, box first — or in a
/// grouped form, its label at the leading edge and the control at the
/// trailing one, as a `LabeledContent`'s row is laid out there
/// (`_GroupedLabeledRow`), the way SwiftUI's grouped form lays out a toggle.
private struct _FormControlRowView: View {
    let view: AnyView
    let parts: (label: AnyView, control: AnyView)?
    let indent: Int
    @Environment(\.labeledContentPlacement) private var placement

    var body: some View {
        if placement == .groupedFormRow, let parts {
            _GroupedLabeledRow(label: parts.label, content: parts.control)
        } else {
            view.padding(.leading, indent)
        }
    }
}

/// A row's natural layout (``baseRowView(_:pillar:)``) inside the modifiers
/// that were written on it (``_FormRow/rewrap``).
@MainActor @ViewBuilder
private func rewrappedRowView(_ row: _FormRow, pillar: Int) -> some View {
    if let rewrap = row.rewrap {
        rewrap(AnyView(baseRowView(row, pillar: pillar)))
    } else {
        baseRowView(row, pillar: pillar)
    }
}

/// Builds one row's view. An explicit ``View/formRowAlignment(_:)``
/// frames the row to `contentWidth` at that alignment (columns only); otherwise a
/// button defaults to right-aligned and every other kind keeps its natural width.
/// `contentWidth` is 0 in grouped, where row-level horizontal alignment doesn't
/// apply.
@MainActor @ViewBuilder
private func formRowView(_ row: _FormRow, pillar: Int, contentWidth: Int) -> some View {
    let base = rewrappedRowView(row, pillar: pillar)
    if contentWidth > 0, let alignment = row.alignment {
        // Explicit override (e.g. left-align a button that defaults to the right).
        base.frame(width: contentWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
    } else if contentWidth > 0, case .button = row.kind {
        // Buttons default to the content edge in columns.
        base.frame(width: contentWidth, alignment: .trailing)
    } else {
        base
    }
}

/// A bold section header right-aligned to the pillar (left-aligned when there are
/// no field labels). There is no direct AppKit analogue for a header in a columns
/// form, so it is aligned with the field labels.
///
/// At LEAST the pillar, not exactly it: the pillar is the field labels' width, and
/// a header is not a field label. Framed to exactly the pillar, a header wider than
/// every label was cut — "Measurements" over a column sized by "Page height" drew
/// as "Measuremen…". Wider, it simply runs on past the column's edge, on a line of
/// its own.
@MainActor @ViewBuilder
private func sectionHeaderView(_ header: AnyView, pillar: Int) -> some View {
    if pillar > 0 {
        header.bold().frame(minWidth: pillar, alignment: .trailing)
    } else {
        header.bold()
    }
}

/// Columns layout for one element: rows pillar-aligned; a section renders a
/// leading blank line (except the first), its bold right-aligned header, its
/// rows, then its footer — all to one pillar.
@MainActor @ViewBuilder
private func columnsElementView(
    _ element: _FormElement, pillar: Int, contentWidth: Int, isFirst: Bool
) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar, contentWidth: contentWidth)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst { Text("") }  // blank line between sections
            if let header = section.header { sectionHeaderView(header, pillar: pillar) }
            ForEach(_indexed(section.rows)) { row in
                columnsSectionRowView(row.value, pillar: pillar, contentWidth: contentWidth)
            }
            if let footer = section.footer { footer }
        }
    case .group(let elements, let branch):
        groupView(branch: branch, spacing: 0) {
            ForEach(_indexed(elements)) { entry in
                columnsElementView(
                    entry.value, pillar: pillar, contentWidth: contentWidth,
                    isFirst: isFirst && entry.id == 0)
            }
        }
    }
}

/// One element of a columns section: a row, or an `if`'s rows (a section's
/// rows hold no section).
@MainActor @ViewBuilder
private func columnsSectionRowView(_ element: _FormElement, pillar: Int, contentWidth: Int) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar, contentWidth: contentWidth)
    case .group(let elements, let branch):
        groupView(branch: branch, spacing: 0) {
            ForEach(_indexed(elements)) { entry in
                columnsSectionRowView(entry.value, pillar: pillar, contentWidth: contentWidth)
            }
        }
    case .section:
        EmptyView()
    }
}

/// The elements of an `if` or of an arm of an `if`/`else`
/// (``_FormElement/group(_:branch:)``), stacked `spacing` apart as the form
/// stacks its elements, under the arm's branch. Erased, as the element views
/// that call it are what it draws. TUIkitFoundation identifies and erases the
/// stack (`erasedID(_:)`): `id(_:)`'s result names a type only it can see, which
/// this module would look up at run time on every call (CONTRIBUTING.md,
/// "Crossing a module boundary").
@MainActor
private func groupView(branch: String?, spacing: Int, @ViewBuilder _ elements: () -> some View) -> AnyView {
    let stack = VStack(alignment: .leading, spacing: spacing, content: elements)
    guard let branch else { return AnyView(stack) }
    return stack.erasedID(branch)
}

/// Grouped layout for one element: a section is a bordered box (its title bold
/// above it); a bare row renders as-is. Every section box is framed to the same
/// `contentWidth` (the form's widest row) so the boxes' right borders line up
/// vertically, and buttons right-align to that edge inside the box — matching the
/// columns layout's button rule.
@MainActor @ViewBuilder
private func groupedElementView(_ element: _FormElement, pillar: Int, contentWidth: Int) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar, contentWidth: contentWidth)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if let header = section.header { header.bold() }
            if section.isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(_indexed(section.rows)) { row in
                        groupedSectionRowView(row.value, pillar: pillar)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, 1)
                // Bordered, and erased, by TUIkitFoundation: `border()`'s
                // result names a type only it can see (`groupView`). Erasing
                // costs this box's static member count nothing: the footer
                // beside it is an `AnyView` already.
                .erasedBorder()
                if let footer = section.footer { footer }
            }
        }
    case .group(let elements, let branch):
        groupView(branch: branch, spacing: 1) {
            ForEach(_indexed(elements)) { entry in
                groupedElementView(entry.value, pillar: pillar, contentWidth: contentWidth)
            }
        }
    }
}

/// One element inside a grouped section's box: a row, or an `if`'s rows
/// (a section's rows hold no section).
@MainActor @ViewBuilder
private func groupedSectionRowView(_ element: _FormElement, pillar: Int) -> some View {
    switch element {
    case .row(let row):
        groupedRowView(row, pillar: pillar)
    case .group(let elements, let branch):
        groupView(branch: branch, spacing: 0) {
            ForEach(_indexed(elements)) { entry in
                groupedSectionRowView(entry.value, pillar: pillar)
            }
        }
    case .section:
        EmptyView()
    }
}

/// One row inside a grouped section's box. The box is framed to a uniform width,
/// so a button right-aligns to *that* width with a leading `Spacer` (not a fixed
/// frame — the form's `contentWidth` is measured at the wider form edge and would
/// overshoot the bordered box); everything else keeps its natural per-kind layout.
@MainActor @ViewBuilder
private func groupedRowView(_ row: _FormRow, pillar: Int) -> some View {
    if case .button = row.kind {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            rewrappedRowView(row, pillar: pillar)
        }
    } else {
        rewrappedRowView(row, pillar: pillar)
    }
}

// MARK: - Internal Core View

/// Renders a ``Form`` per the active ``FormStyle``. Built-in styles
/// (columns/grouped/automatic) are laid out here directly — they need the form's
/// concrete content type to extract its rows, which the type-erased
/// ``FormStyleConfiguration`` can't carry — while a custom style is dispatched
/// through its ``FormStyle/makeBody(configuration:)``.
private struct _FormLayout<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never {
        fatalError("_FormLayout renders via Renderable")
    }

    /// Measures the column it is about to build, rather than BUILDING it.
    ///
    /// This was `measureFixedByRendering(self, …)`, which renders the whole form
    /// to report its size — so a form was assembled twice per frame, and each
    /// assembly is two measure walks over every row (the pillar and the content
    /// width) plus a render of the composed column. On the
    /// `app-shapes/settings-form` scenario — sixty bound controls, the shape of
    /// an ordinary preferences window — `measureFixedByRendering` was 81% of
    /// the frame and `_FormLayout.sizeThatFits` alone was 73.6% (Instruments,
    /// release, 2026-09-22).
    ///
    /// Still `.fixed`, exactly as before: a form hugs its content on both axes,
    /// and the column it composes is the content. What changed is that the
    /// column is measured instead of drawn.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.hasExplicitWidth = false
        if let width = proposal.width { measureContext.availableWidth = width }
        if let height = proposal.height { measureContext.availableHeight = height }
        guard let composed = composedColumn(context: measureContext) else {
            // A custom style renders itself through `makeBuffer`, and there is
            // nothing structural here to measure.
            return measureFixedByRendering(self, proposal: proposal, context: context)
        }
        let size = measureChild(composed, proposal: proposal, context: measureContext)
        return ViewSize.fixed(size.width, size.height)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let composed = composedColumn(context: context) else {
            // Custom style: hand it the (type-erased) content to render itself.
            // The body sees the style outside this one, so a `Form(configuration)`
            // in it lays the form out as that style would.
            var bodyContext = context
            bodyContext.environment.formStyleChain = context.environment.formStyleChain.inside
            return context.environment.formStyle.makeBuffer(
                configuration: FormStyleConfiguration(content: AnyView(content)), context: bodyContext)
        }
        return TUIkitView.renderToBuffer(composed, context: context)
    }

    /// The column this form is, for whichever built-in style is in force, or
    /// `nil` for a custom style (which builds its own buffer and has no column).
    ///
    /// One function so the measure and the render cannot compose different
    /// trees — the pillar and the content width are derived here, and both
    /// callers get the same answer for the same context.
    private func composedColumn(context: RenderContext) -> AnyView? {
        let style = context.environment.formStyle
        let grouped: Bool
        if style is GroupedFormStyle {
            grouped = true
        } else if style is ColumnsFormStyle || style is AutomaticFormStyle {
            grouped = false
        } else {
            return nil
        }

        let elements = formElements(from: content, in: context.withChildIdentity(type: _FormContentWalk.self))
        let pillar = pillarWidth(of: elements, context: context)
        // The widest non-button row drives both layouts now: in columns it's the
        // edge buttons right-align to; in grouped it's the shared box width.
        let contentWidth = contentWidth(of: elements, pillar: pillar, context: context)

        let column = VStack(alignment: .leading, spacing: grouped ? 1 : 0) {
            ForEach(_indexed(elements)) { entry in
                if grouped {
                    groupedElementView(entry.value, pillar: pillar, contentWidth: contentWidth)
                } else {
                    columnsElementView(
                        entry.value, pillar: pillar, contentWidth: contentWidth,
                        isFirst: entry.id == 0)
                }
            }
        }
        // A grouped form is a scroll view on macOS, and takes `contentMargins`
        // as one does (measured): around its sections, and not passed on to
        // them. TUIkit's form does not scroll, so they are its padding. A
        // columns form ignores them, as macOS's does.
        let margins = context.environment.contentMargins
        if grouped, !margins.isEmpty, !margins.content.isZero {
            return AnyView(
                column
                    .environment(\.labeledContentPlacement, .groupedFormRow)
                    .transformEnvironment(\.contentMargins) { $0 = ContentMargins() }
                    .padding(margins.content))
        }
        // A grouped form's labelled rows spread across it, its own and any
        // `LabeledContent` drawn in one (`_GroupedLabeledRow`).
        if grouped { return AnyView(column.environment(\.labeledContentPlacement, .groupedFormRow)) }
        return AnyView(column)
    }

    /// The shared pillar: the widest field label across every row (sections
    /// included), so all field labels right-align to one column — each behind
    /// the leading padding written on its row, which widens the column as it
    /// does SwiftUI's (``_FormRow/leadingInset``).
    private func pillarWidth(of elements: [_FormElement], context: RenderContext) -> Int {
        // `.labelsHidden()` on a form takes the label COLUMN away, not just
        // the words in it: a pillar sized to labels nobody draws would indent
        // every control by the width of the longest invisible caption.
        guard !context.environment.controlLabelsAreHidden else { return 0 }
        return formRows(of: elements)
            .compactMap { row -> Int? in
                guard case .field(let label, _) = row.kind, !row.hidesLabel else { return nil }
                return row.leadingInset
                    + measureChild(label, proposal: ProposedSize(width: nil, height: nil), context: context).width
            }
            .max() ?? 0
    }

    /// The form's content width: the widest non-button row (buttons are sized to
    /// this so they right-align to the content edge in columns).
    private func contentWidth(of elements: [_FormElement], pillar: Int, context: RenderContext) -> Int {
        formRows(of: elements)
            .compactMap { row -> Int? in
                if case .button = row.kind { return nil }
                return measureChild(
                    formRowView(row, pillar: pillar, contentWidth: 0),
                    proposal: ProposedSize(width: nil, height: nil), context: context
                ).width
            }
            .max() ?? 0
    }
}

// MARK: - A Field Row

/// A labelled row of a form: the label right-aligned in the form's label column,
/// then its content — or, under a custom ``LabeledContentStyle``, whatever that
/// style draws, which takes the row over as it does outside a form.
private struct _FormFieldRow: View {
    let label: AnyView
    let content: AnyView
    let pillar: Int
    /// The cells the modifiers written on the row put before it, which the
    /// label column already counts: the label's share of the pillar is what is
    /// left (``_FormRow/leadingInset``).
    let leadingInset: Int
    /// Whether `.labelsHidden()` written on the row hides its label
    /// (``_FormRow/hidesLabel``); a grouped row's label hides itself.
    let hidesLabel: Bool
    @Environment(\.labeledContentStyleChain) private var styles
    @Environment(\.labeledContentPlacement) private var placement

    @ViewBuilder var body: some View {
        if !styles.isRoot {
            _StyledLabeledContent(
                configuration: LabeledContentStyleConfiguration(label: label, content: content))
        } else if placement == .groupedFormRow {
            // A grouped form has no label column: each row spreads across.
            _GroupedLabeledRow(label: label, content: content)
        } else if pillar == 0 {
            // A pillar of zero means there is no label column: every label
            // measured empty, or `.labelsHidden()` withheld them all. The gap in
            // front of the content goes with the column — a form of hidden labels
            // should read as a column of controls, not a column of controls
            // indented by one for a label that is not there.
            content
        } else {
            // The gap is the label's trailing padding, not the stack's
            // spacing: a label framed to no width at all — a row whose leading
            // padding fills the column — would take the stack's spacing with
            // it, and its content would start a cell short of the others'.
            HStack(spacing: 0) {
                if !hidesLabel {
                    label.frame(width: max(0, pillar - leadingInset), alignment: .trailing).padding(.trailing, 1)
                } else {
                    // A hidden label keeps no cell of the column but its place:
                    // the value stays in the value column.
                    Color.clear.frame(width: max(0, pillar - leadingInset) + 1, height: 1)
                }
                content
            }
        }
    }
}

// MARK: - From a Configuration

extension Form where Content == FormStyleConfiguration.Content {
    /// Creates a form based on a form style configuration.
    ///
    /// Use it inside a ``FormStyle``'s ``FormStyle/makeBody(configuration:)``
    /// to lay the form out as the style outside the custom one would, and add
    /// to it.
    ///
    /// - Parameter configuration: The properties of the form.
    public init(_ configuration: FormStyleConfiguration) {
        self.init { configuration.content }
    }
}

// MARK: - Environment without reflection

extension _FormFieldRow: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _styles.resolveEnvironment(environment)
        _placement.resolveEnvironment(environment)
    }
}
