//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuSections.swift
//
//  A `Section` in a menu, drawn as SwiftUI's macOS menus draw one: set off
//  from the items around it by separators, under its header as a title that
//  is no item.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A menu's items, each `Section` among them drawn as a menu draws one —
/// what every TUI menu (a pop-up `Menu`, a `.contextMenu`, an inline
/// `Menu`) stacks as its rows.
///
/// Measured on macOS 15.8
/// (`Tools/SwiftUIProbes/Sections and subview counting/menuapp.swift`, SwiftUI's own `NSMenu` for a
/// `CommandMenu` read back): each section is wrapped in separators and its
/// header is a section-header item — a small grey title, never highlighted or
/// chosen — followed by its items; a menu shows no separator at its top or
/// bottom and never two in a row. Outside a menu a section is its parts with no
/// styling (decisions B16); a menu is the container that styles them, as a
/// `List` is.
///
/// So the items are resolved keeping their sections whole, and each is spliced
/// back as rows: a separator, its header drawn under the section-header chrome
/// role (bold and dimmed, a `List` section header's look), its content's and
/// footer's views, and a separator. A separator at either end, or beside
/// another (one the app wrote too), is dropped. Every other item is handed
/// over as it was, at the identity it had — one a menu sets off as a section
/// though it is none (``MenuSectionDrawing``, an `.inline` `Picker`) between
/// separators of the section's kind, which it is told not to draw itself.
struct _MenuSectionedItems<Items: View>: View, Renderable, Layoutable, ChildViewProvider {
    let items: Items

    var body: Never {
        fatalError("_MenuSectionedItems renders via Renderable")
    }

    /// One row of the menu before separators are collapsed.
    private enum Entry {
        /// An item, a section's header or one of its views.
        case row(ChildView)
        /// A separator the app wrote: kept, and taken as one for a section.
        case divider(ChildView)
        /// A separator a section adds, before or after it — drawn only where it
        /// separates two rows that are not already separated.
        case sectionEdge(ChildView)
    }

    func childViews(context: RenderContext) -> [ChildView] {
        // The type says whether a section — or a view a menu sets off as one —
        // can be among the items at all, so a menu of buttons resolves them
        // exactly as it always did.
        let mayHoldSections = mayHandOver(.section, in: items)
        guard mayHoldSections || mayHandOver(.menuSection, in: items) else {
            return resolveChildViews(from: items, context: context)
        }
        let children = resolveChildViews(from: items, context: mayHoldSections ? context.keepingSectionsWhole() : context)
        // Nothing among them to set off — the common case, under a menu style's
        // `configuration.content`, which the type gate cannot see into — leaves
        // the children as they are, before any entry is made: making one walks
        // the child's wrappers for a `Divider`. Built for every row of every
        // inline menu and thrown away, that was 3% of a cold `menus` frame.
        guard let first = children.firstIndex(where: { sectionParts(of: $0) != nil || menuSectionDrawing(of: $0, in: context) })
        else { return children }
        var entries: [Entry] = children[..<first].map {
            throughWrappers($0.wrappedView, as: Divider.self) != nil ? .divider($0) : .row($0)
        }
        for child in children[first...] {
            guard let parts = sectionParts(of: child) else {
                if !appendSetOff(child, to: &entries, in: context) {
                    entries.append(throughWrappers(child.wrappedView, as: Divider.self) != nil ? .divider(child) : .row(child))
                }
                continue
            }
            let scope = pinnedScope(of: child, in: context)
            let scoped = parts.scopedParts(in: scope)
            entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.before, in: scope)))
            if !(parts.header is EmptyView) {
                entries.append(
                    .row(ChildView(_MenuSectionHeader(header: parts.header)).pinningIdentity(to: scoped[0].scope.identity)))
            }
            for part in scoped.dropFirst() {
                for row in resolveChildViews(from: part.view, context: part.scope) {
                    let pinned = row.pinningIdentity(to: part.scope.identity)
                    if !appendSetOff(pinned, to: &entries, in: context) { entries.append(.row(pinned)) }
                }
            }
            entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.after, in: scope)))
        }
        return Self.collapsed(entries)
    }

    /// Appends `child`, an item that is no `Section`, between the separators
    /// of a section, if the menu sets it off as one
    /// (``menuSectionDrawing(of:in:)``) — wrapped to draw none of its own.
    /// Answers whether it did; the caller appends any other item itself.
    private func appendSetOff(_ child: ChildView, to entries: inout [Entry], in context: RenderContext) -> Bool {
        guard menuSectionDrawing(of: child, in: context) else { return false }
        let scope = pinnedScope(of: child, in: context)
        entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.before, in: scope)))
        entries.append(.row(child.rewrapped(by: Self.separatorsPlaced)))
        entries.append(.sectionEdge(separator(MenuSectionSeparatorIndex.after, in: scope)))
        return true
    }

    /// What a view the menu sets off as a section is wrapped in, so that it
    /// draws no separators of its own
    /// (``EnvironmentValues/menuPlacesSectionSeparators``).
    private static var separatorsPlaced: EnvironmentModifier<EmptyView, Bool> {
        EnvironmentModifier(content: EmptyView(), keyPath: \.menuPlacesSectionSeparators, value: true)
    }

    /// A separator a section adds, at an identity of its own under the
    /// section's.
    private func separator(_ index: Int, in scope: RenderContext) -> ChildView {
        ChildView(Divider(), childIndex: index).pinningIdentity(to: scope.identity)
    }

    /// The rows, with the separators a section adds kept only where they
    /// separate: none at the menu's top or bottom, none beside another.
    private static func collapsed(_ entries: [Entry]) -> [ChildView] {
        var rows: [ChildView] = []
        var lastWasSeparator = true
        var pendingEdge: ChildView?
        for entry in entries {
            switch entry {
            case .sectionEdge(let edge):
                if !lastWasSeparator, pendingEdge == nil { pendingEdge = edge }
            case .divider(let divider):
                pendingEdge = nil
                rows.append(divider)
                lastWasSeparator = true
            case .row(let row):
                if let edge = pendingEdge { rows.append(edge) }
                pendingEdge = nil
                rows.append(row)
                lastWasSeparator = false
            }
        }
        return rows
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderStackedVertically(childViews(context: context), context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureStackedVertically(childViews(context: context), proposal: proposal, context: context)
    }
}

/// Child indices for the separators a menu section adds, under the section's
/// own scope: after its parts' (0, 1 and 2, ``SectionParts/scopedParts(in:)``).
/// Under a view set off as a section (``MenuSectionDrawing``) too, whose body
/// goes one step in under a type of its own.
private enum MenuSectionSeparatorIndex {
    static let before = 3
    static let after = 4
}

// MARK: - Views Set Off as Sections

/// A view a menu sets off by separators as it does a `Section`, though it is
/// none — an `.inline` `Picker` (TUIPickers), which SwiftUI builds in a menu
/// exactly as it builds a section: a separator, its label as a section header,
/// its options, a separator (measured on macOS 15.8, `Tools/SwiftUIProbes/Menu
/// items and alert buttons/inline.out`). So its separators follow the
/// section's rule: none at the menu's top or bottom, never two in a row
/// (`shown.out`: AppKit draws a menu so, whatever separators it holds).
///
/// The menu places them (``_MenuSectionedItems``) and tells the view, through
/// ``EnvironmentValues/menuPlacesSectionSeparators``, to draw none of its own.
/// The menu finds the view among its items, under the wrappers round it that
/// say the context they lay it out in (`.pickerStyle(.inline)` written on it,
/// `.disabled`); where it cannot see it — inside a view of the app's own, or
/// under a wrapper that does not say — the view is told nothing, and draws its
/// separators itself, wherever it stands.
@MainActor
package protocol MenuSectionDrawing {
    /// Whether, laid out in `context` — its own, every wrapper round it
    /// applied — this view draws as a section of the pop-up menu it is in.
    func drawsAsMenuSection(in context: RenderContext) -> Bool
}

/// Whether `child` is a view the menu sets off as a section
/// (``MenuSectionDrawing``): found under the wrappers round it that say the
/// context they lay it out in, each one's applied to the context the child is
/// drawn in, so the view answers in the environment it will see. A wrapper
/// that does not say stops the look.
///
/// The view's type is asked first, and that answer is kept per type
/// (``mayHandOver(_:_:)``): a menu whose content the type gate cannot see
/// into — a menu style's `configuration.content` — resolves its rows and asks
/// this of every one of them on every render it is not served, and a walk of
/// the wrappers with a cast at each was 4.2% of a cold `menus` frame. Only an
/// item whose type may hold one is looked for through the wrappers, and only
/// one that does pays for the walk that applies them.
@MainActor
private func menuSectionDrawing(of child: ChildView, in context: RenderContext) -> Bool {
    guard typeMayDrawAsMenuSection(child.wrappedView),
        throughWrappers(child.wrappedView, as: (any MenuSectionDrawing).self) != nil
    else { return false }
    var view: any View = child.wrappedView
    var scope = child.renderContext(under: context)
    while true {
        if let drawing = view as? any MenuSectionDrawing { return drawing.drawsAsMenuSection(in: scope) }
        guard let wrapper = view as? any SingleContentWrapper, let inner = wrapper.wrappedContentContext(scope) else {
            return false
        }
        view = wrapper.wrappedContent
        scope = inner
    }
}

/// Whether a view of `view`'s type may be one a menu sets off as a section:
/// the type gate's answer, the existential opened.
@MainActor
private func typeMayDrawAsMenuSection<V: View>(_ view: V) -> Bool {
    mayHandOver(.menuSection, V.self)
}

private struct MenuPlacesSectionSeparatorsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the menu draws this view's separators, having set it off as a
    /// section (``MenuSectionDrawing``): set round such a view alone, by the
    /// menu that places them, so a view it could not find draws its own.
    package var menuPlacesSectionSeparators: Bool {
        get { self[MenuPlacesSectionSeparatorsKey.self] }
        set { self[MenuPlacesSectionSeparatorsKey.self] = newValue }
    }
}

/// A menu section's header: drawn under the section-header chrome role, as a
/// `List`'s is, and never a row the menu highlights or chooses — it publishes
/// no row, as a `Divider` does not. Also the title over an inline `Picker`'s
/// options in a menu, and over a section of a `Picker`'s submenu
/// (TUIPickers).
nonisolated package struct _MenuSectionHeader: View, Renderable, Layoutable {
    let header: any View

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIPickers makes these.
    package init(header: any View) {
        self.header = header
    }

    @MainActor package var body: Never {
        fatalError("_MenuSectionHeader renders via Renderable")
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(header, context: sectionChromeContext(context, .sectionHeader))
    }

    @MainActor package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(header, proposal: proposal, context: sectionChromeContext(context, .sectionHeader))
    }
}
