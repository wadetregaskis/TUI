//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineGroup.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - OutlineGroup

/// A tree, drawn from a collection and a key path to each element's children.
///
/// ```swift
/// struct Node: Identifiable {
///     let id = UUID()
///     let name: String
///     var children: [Node]?      // nil = a leaf
/// }
///
/// ScrollView {
///     OutlineGroup(tree, children: \.children) { node in
///         Text(node.name)
///     }
/// }
/// ```
///
/// ```
///   ▼ Sources
///       ▶ TUI
///       ▼ TUICore
///           Rendering
///           Extensions
///     README.md
/// ```
///
/// With the mouse it is the **triangle** that discloses, not the whole row —
/// unlike ``DisclosureGroup``, which has no competition for its row, an outline
/// row's text belongs to whatever the outline is inside, so that a ``List`` can
/// select the node whose triangle just opened it. A single cell is a mean
/// target, so the triangle quietly extends over the blank cell on either side:
/// four cells to hit, one glyph to read.
///
/// Where nothing WILL claim the text, that reasoning says the row is free: in a
/// ``List`` with no selection binding a click anywhere on the row discloses it,
/// since the click has no selection to make (`8c363353`). A child view with a
/// click handler of its own still wins, and a bare `OutlineGroup` — in a
/// `VStack`, a `ScrollView` — still discloses only from its triangle.
///
/// ## From the keyboard
///
/// On its own — in a `VStack`, a `ScrollView` — each branch's triangle is a Tab
/// stop, and **Return** or **Space** opens or closes it, as any button would.
/// **Right** opens it and **Left** closes it, exactly as in the `List` form
/// below, so the same tree answers the same keys whatever it was put inside.
/// (Without the list's ladder: there is no row cursor here to walk out of a
/// subtree, so a Left with nothing left to close is plain focus movement.)
///
/// Inside a ``List`` the row is the focusable and the triangle is not, because
/// a row has a *selection* as well as an action and the two must not compete:
///
/// - **Space** selects the focused row, as it does in any list.
/// - **Return** activates it, which for a branch means disclosing it — unless
///   the app claims Return with the `primaryAction` of
///   ``View/contextMenu(forSelectionType:menu:primaryAction:)``, which wins.
///   A leaf has nothing to disclose, and Return selects it, as Space does.
/// - **Right** opens the focused branch and **Left** closes it, so a tree stays
///   reachable when the app has taken Return. Both fall through on a leaf, on a
///   branch already in that state, and on a list that is not a tree at all.
/// - **⌥Right** and **⌥Left** carry that down the whole subtree — everything
///   under the branch, however deep, in one keystroke. The Finder's gesture,
///   and the reason a recursive collapse also folds the descendants: opening
///   the branch again shows it as it was left, not as it was before.
///
/// - Note: ⌥-arrow depends on the terminal forwarding Option on an arrow key,
///   which not all of them do — Apple Terminal spends ⌥←/⌥→ on its own
///   word-motion bindings unless "Use Option as Meta key" is on. See
///   `Documentation/Terminals/Terminal compatibility survey.md`. Plain Right and Left reach
///   every branch regardless; the Option form is an accelerator, never the
///   only way in.
///
/// The glyphs and the indent step are ``DisclosureGroup``'s. A leaf's label
/// lines up with its siblings' labels rather than with their triangles, so a
/// column of names stays a column.
///
/// `children` is the whole distinction between a branch and a leaf: `nil` is a
/// leaf and gets no triangle; a non-`nil` collection is a group, **even when it
/// is empty** — which is SwiftUI's rule, and the right one, since "this folder
/// has nothing in it" is worth being able to say.
///
/// ## Its nodes are the container's rows
///
/// An outline emits one row per *visible* node to whatever contains it, exactly
/// as ``ForEach`` emits one per element — a `VStack` lays them out as siblings,
/// and a `List` makes each one a selectable row of its own, which is what
/// `List(_:children:)` is. The depth lives in each row's leading padding rather
/// than in the view hierarchy, so a deep tree is not a deep view hierarchy, and
/// a closed branch's descendants are neither built nor measured — the
/// flattening walk simply stops there.
///
/// In a `List` its rows are windowed, as a `ForEach`'s are: the list counts the
/// open nodes and builds a row only for those it draws, about a screenful,
/// however much of the tree is open. The open nodes are kept from pass to pass
/// while the tree and its open branches are the same, so a scroll or a cursor
/// move walks no tree at all.
///
/// A container asks for those rows before it would ever draw the outline as
/// one view. Where nothing lays them out — as a scroll view's whole content,
/// the example above — its `body` stacks them, and in scroll content past a
/// few hundred open rows builds only those on screen, as a `LazyVStack` would.
///
/// The expansion is the group's own, starting closed, exactly as in SwiftUI,
/// unless the app hands it one of its own (below).
///
/// ## The app's own expansion (TUI only)
///
/// SwiftUI's `OutlineGroup` takes no expansion: its branches start closed and
/// only the user opens them. TUI's every view initializer also takes an
/// `expansion:` binding, defaulted to `nil`, so a SwiftUI call site compiles
/// and behaves as it does in SwiftUI. Handed one, the outline opens exactly the
/// branches whose IDs are in the set, and the user's opening and closing —
/// Right, Left, ⌥Right, ⌥Left, a click on a triangle, and Return or Space on
/// a bare outline's triangle — writes it:
///
/// ```swift
/// @State private var open: Set<File.ID> = [root.id]   // starts open
///
/// List(files, children: \.children, expansion: $open, selection: $selected) { file in
///     Text(file.name)
/// }
///
/// // Find: open a match's ancestors from code, then select it.
/// open.formUnion(ancestors(of: match))
/// selected = match.id
/// ```
///
/// It exists because a tree that starts open, or that code opens, could
/// otherwise only be drawn as nested ``DisclosureGroup``s, each bound to an
/// expansion the app keeps, whose rows are every one built on every frame; an
/// outline keeps its open rows between frames and a `List` builds only the
/// rows it draws, with the outline's expansion or the app's alike. A SwiftUI
/// port drops the argument and goes back to `DisclosureGroup`s. The same
/// argument is on `List(_:children:)` and `Table(_:children:)`.
///
/// - Note: SwiftUI's `OutlineGroup` carries five generic parameters; two of
///   them (`Parent` and `Subgroup`) are phantom — `Parent` is always `Leaf`,
///   and `Subgroup` can only ever be the one `DisclosureGroup` specialization
///   — so TUI declares the three that carry information and drops SwiftUI's
///   `OutlineSubgroupChildren` marker with them. Every initializer is
///   unchanged; only spelling the type out by hand differs. (Same call as
///   ``Gauge``, which likewise drops a generic parameter with no terminal
///   meaning.)
///
/// `OutlineGroup` is not only a view: as in SwiftUI it also builds a table's
/// rows, and it is a view exactly when what it builds is one. It is
/// main-actor isolated as a whole, as its `View` conformance made it.
nonisolated public struct OutlineGroup<Data: RandomAccessCollection, ID: Hashable, Leaf> {
    /// The top-level elements, flattened out of whichever initializer was used
    /// so one implementation serves both the `root` and the collection forms.
    package let roots: [Data.Element]

    /// Each element's stable identity.
    let idKeyPath: KeyPath<Data.Element, ID>

    /// Each element's children — `nil` for a leaf.
    package let childrenKeyPath: KeyPath<Data.Element, Data?>

    /// Builds a node's label.
    package let content: (Data.Element) -> Leaf

    /// The app's expansion, from an `expansion:` argument, or `nil` for the
    /// outline to keep its own (``expansion(context:)``).
    let appExpansion: Binding<Set<ID>>?

    /// Whether a `List` windows these rows (``windowedListRows(context:)``):
    /// `false` extracts every row on every pass, as a `Section` among other
    /// rows does — the drawing the windowed one is tested against.
    package var windowsListRows = true

    /// The bridge a hierarchical ``List`` drives the disclosure through.
    ///
    /// A reference type deliberately: this value is rebuilt every frame, and
    /// the list re-reads it every frame too, so the pair always agree — but the
    /// closure inside has to survive from the render that installs it to the
    /// keystroke that calls it.
    let activation = OutlineActivation()
}

@MainActor extension OutlineGroup: View where Leaf: View {
    /// The rows, stacked, for where nothing lays them out
    /// (`OutlineGroup+Drawn.swift`). A container that does — a stack, a
    /// `List`, a `Section` — takes the outline apart into its rows instead
    /// (``childViews(context:)``, `extractListRows(context:)`) and never
    /// asks for this.
    public var body: some View {
        _OutlineGroupCore(outline: self)
    }
}

// MARK: - Disclosure from the list's own row cursor

/// How a hierarchical ``List`` reaches the disclosure of the row its cursor is
/// on.
///
/// The two halves are built in one initializer but only meet at render: an
/// outline does not learn where its expansion lives until it is handed a
/// context, while the list's key handling has to reach it from a handler
/// configured before any key arrives. This reference type is what both hold —
/// the outline fills it in each pass, the list calls through it.
///
/// Not actor-isolated, for the same reason ``ItemListHandler``'s
/// `primaryAction` is a plain closure: key dispatch reaches the handler from a
/// nonisolated context, and rendering — the only thing that ever writes here —
/// is single-threaded on the run loop.
@MainActor
package protocol OutlineRowActivating {
    /// Opens, closes or toggles the node with this id.
    ///
    /// - Parameters:
    ///   - id: The row's id, as the list knows it.
    ///   - target: `true` to open, `false` to close, `nil` to toggle.
    ///   - includingDescendants: Whether to carry the same state down the
    ///     node's whole subtree — every branch under it, however deep, and not
    ///     only the ones currently on screen. A collapse takes the descendants
    ///     with it, so re-opening the node shows it as it was left.
    /// - Returns: Whether anything moved — `false` for a leaf, for an unknown
    ///   id, and for a subtree already in the requested state, so the key falls
    ///   through to whatever else wants it.
    @discardableResult
    func setRowExpanded(_ id: AnyHashable, to target: Bool?, includingDescendants: Bool) -> Bool

    /// The row this one sits under, or `nil` for a root row (and for an id this
    /// frame's tree does not know).
    ///
    /// Left needs it: on a row that is not an open branch, the key walks OUT of
    /// the subtree instead of dying — the outline-view behaviour, where Left
    /// either closes what you are in or takes you to what contains it.
    func parentRowID(of id: AnyHashable) -> AnyHashable?
}

/// The mutable half of ``OutlineRowActivating``, refreshed every pass.
final class OutlineActivation {
    /// Installed by ``OutlineGroup/extractListRows(context:)`` with that
    /// frame's real expansion box captured. `nil` before the first render.
    var apply: ((AnyHashable, Bool?, Bool) -> Bool)?

    /// This frame's child → parent map, in the ids the LIST knows rows by.
    /// Installed alongside ``apply``; `nil` before the first render.
    var parentOf: ((AnyHashable) -> AnyHashable?)?
}

// MARK: - The rows

@MainActor extension OutlineGroup where Leaf: View {
    /// The rows to draw, depth-first, stopping at every closed branch.
    ///
    /// A walk of the open part of the tree, reading two key paths a node and
    /// building no row: a stack's rows are made from it as they are drawn, and
    /// a `List` keeps it from pass to pass while nothing in it can have
    /// changed (``OutlineVisibleNodes``), building only the rows it draws.
    func visibleNodes(expanded: Set<ID>) -> [Node] {
        var nodes: [Node] = []
        // An explicit stack rather than recursion: a deep tree must not put the
        // render pass any nearer the stack limit than the view hierarchy
        // already does. Pushed in reverse, so the top of the stack is always
        // the next node in reading order.
        var stack: [(element: Data.Element, depth: Int, parent: Int)] = roots.reversed().map { ($0, 0, -1) }
        while let (element, depth, parent) = stack.popLast() {
            let id = element[keyPath: idKeyPath]
            let children = element[keyPath: childrenKeyPath]
            let isOpen = expanded.contains(id)
            nodes.append(
                Node(
                    id: id, element: element, depth: depth, isBranch: children != nil,
                    isExpanded: isOpen, parent: parent))
            guard let children, isOpen else { continue }
            let index = nodes.count - 1
            for child in children.reversed() {
                stack.append((child, depth + 1, index))
            }
        }
        return nodes
    }

    /// A walk that answers "every branch in this element's subtree, itself
    /// first" — the ids a recursive open or close has to write.
    ///
    /// Walks the DATA rather than the visible nodes, because that is the whole
    /// point: the descendants of a closed branch are exactly the ones that were
    /// never flattened, and they are what "everything under this" means. Leaves
    /// contribute nothing — there is no state to hold for a node that cannot
    /// open.
    ///
    /// Handed back as a closure over the two key paths rather than left as a
    /// method, because its one caller is the disclosure closure the list keeps,
    /// which key dispatch reaches from OUTSIDE the main actor. A method would
    /// make that closure read `self` — a main-actor-isolated view — where a
    /// captured pair of key paths is just two values.
    ///
    /// Iterative for the same reason ``visibleNodes(expanded:)`` is: a deep
    /// tree must not put the render pass any nearer the stack limit than the
    /// view hierarchy already does.
    func subtreeBranchWalk() -> (Data.Element) -> [ID] {
        let idOf = idKeyPath
        let childrenOf = childrenKeyPath
        return { root in
            var ids: [ID] = []
            var stack = [root]
            while let current = stack.popLast() {
                guard let children = current[keyPath: childrenOf] else { continue }
                ids.append(current[keyPath: idOf])
                stack.append(contentsOf: children)
            }
            return ids
        }
    }

    /// The view for one node's row.
    ///
    /// - Parameter rowOwnsFocus: Whether something else — a `List`'s own row
    ///   cursor — is the focusable here. When it is, the triangle must not be a
    ///   second Tab stop inside the row: it would take the row's Space with it,
    ///   and a tree of N branches would add N stops nobody asked for.
    func row(
        for node: Node, expansion: OutlineExpansion<ID>, rowOwnsFocus: Bool = false
    ) -> _OutlineRow<Data.Element, ID, Leaf> {
        _OutlineRow(
            element: node.element, id: node.id, depth: node.depth, isBranch: node.isBranch,
            isExpanded: node.isExpanded, expansion: expansion, rowOwnsFocus: rowOwnsFocus,
            content: content)
    }

    /// Where the open node ids are kept: the app's binding, where it handed
    /// one, else the outline's own persistent set.
    ///
    /// The outline's own is kept in the render-pass `StateStorage` rather than
    /// in an `@State` property, because neither path that draws an outline goes through
    /// `body`: a container asks for ``childViews(context:)`` and a `List` for
    /// ``extractListRows(context:)``, and `@State` is bound during a view's own
    /// render, which never happens. Both of those hand over a context, which is
    /// what this needs anyway.
    ///
    /// The identity is a child step off the container's, keyed by name, so two
    /// outlines in different places keep different sets. Two *siblings* of the
    /// same type in one container would share one — the same collision
    /// `ForEach` has for its rows' state, and for the same reason.
    func expansion(context: RenderContext) -> OutlineExpansion<ID> {
        let identity = context.withChildIdentity(erasedType: Self.self, key: "outline").identity
        guard let storage = context.stateStorage else {
            return appExpansion.map { OutlineExpansion($0) } ?? OutlineExpansion(StateBox([]))
        }
        // Nothing renders this identity, so nothing else will mark it — without
        // this the set is collected at the end of the pass that created it and
        // every branch closes itself again on the next frame. Marked with the
        // app's binding too: the kept rows (``OutlineVisibleNodes``) live here.
        storage.markActive(identity)
        if let appExpansion { return OutlineExpansion(appExpansion) }
        return OutlineExpansion(
            storage.storage(
                for: StateStorage.StateKey(identity: identity, propertyIndex: OutlineStateIndex.expansion), default: []))
    }

    /// A node as it appears on screen (``OutlineNode``).
    typealias Node = OutlineNode<Data.Element, ID>
}

/// A node of an outline as it appears on screen: the element, how deep it
/// sits, whether it has a triangle, which way that triangle points, and the
/// row it sits under.
struct OutlineNode<Element, ID: Hashable> {
    let id: ID
    let element: Element
    let depth: Int
    let isBranch: Bool

    /// Carried on the node rather than re-read per row, so the flattening
    /// walk is the only thing that consults the expansion set — the row
    /// and the walk cannot disagree about which triangle to draw.
    let isExpanded: Bool

    /// The index among the visible nodes of the node this one sits under, or
    /// -1 for a root: what Left walks out to. Read off the walk, which pushed
    /// every child with it, so finding it asks nothing of the tree.
    let parent: Int
}

// MARK: - One row per visible node

@MainActor extension OutlineGroup: ChildViewProvider where Leaf: View {
    /// One child per visible node, keyed by the node's id — so a stack lays the
    /// tree out as a column of siblings, and each row's own state follows its
    /// node rather than its position. The nodes are the kept ones
    /// (`OutlineVisibleNodes`), flattened again only when the tree or its
    /// open branches change.
    public func childViews(context: RenderContext) -> [ChildView] {
        let expansion = expansion(context: context)
        return visibleNodes(context: context, expansion: expansion).nodes.map { child(for: $0, expansion: expansion) }
    }
}

@MainActor extension OutlineGroup: OutlineRowActivating where Leaf: View {
    /// `nonisolated` because key dispatch is: the handler reaches this from
    /// outside the main actor, and everything it touches — a `let` reference
    /// and the closure inside it — is written only by the render loop.
    @discardableResult
    package func setRowExpanded(
        _ id: AnyHashable, to target: Bool?, includingDescendants: Bool
    ) -> Bool {
        activation.apply?(id, target, includingDescendants) ?? false
    }

    package func parentRowID(of id: AnyHashable) -> AnyHashable? {
        activation.parentOf?(id)
    }
}

// MARK: - A row

/// One node's row: the disclosure triangle (when it has one) and the label.
///
/// Its own type rather than a `@ViewBuilder` result so the row has a name —
/// which is what a `ChildView` needs to key each node's identity by.
struct _OutlineRow<Element, ID: Hashable, Leaf: View> {
    let element: Element
    let id: ID
    let depth: Int
    let isBranch: Bool
    let isExpanded: Bool

    /// Where the outline keeps its open nodes, held directly: the persistent
    /// box or the app's binding, so writing to it from the button below
    /// outlives this frame and asks for the next one — which is the whole
    /// reason the row carries it rather than a snapshot of the value.
    let expansion: OutlineExpansion<ID>

    /// Whether the container owns this row's focus — see
    /// ``OutlineGroup/row(for:expansion:rowOwnsFocus:)``.
    let rowOwnsFocus: Bool

    let content: (Element) -> Leaf

    /// Whether the triangle holds the focus — written by a click on a bare row's label,
    /// so the row just clicked is the one Left, Right and Space act on next, as after a
    /// click on the triangle itself.
    @FocusState private var triangleFocused: Bool

    /// The content and behavior of this view.
    @MainActor @ViewBuilder var body: some View {
        if isBranch {
            branchRow
                .padding(.leading, depth * DisclosureMetrics.contentIndent)
        } else {
            // One step further in than its depth, so a leaf's label lands in
            // the same column as a sibling branch's label rather than under
            // that branch's triangle.
            content(element)
                .padding(.leading, (depth + 1) * DisclosureMetrics.contentIndent)
        }
    }

    /// A branch's row: the triangle and the label — and, in a bare outline, the label
    /// discloses too.
    ///
    /// Inside a `List` only the TRIANGLE toggles, not the whole row: the rest of the row
    /// is the list's, which is what lets it select the node the triangle discloses
    /// (e42fcef2 narrowed the target for exactly that). A bare `OutlineGroup` has no list
    /// to claim the text, and the narrowing left a click on it doing nothing at all. So
    /// there, and only there, the row gets a click target of its own — BEHIND its content,
    /// so the triangle and anything interactive in the label keep their clicks. In a list
    /// the same region would sit in front of the list's and swallow its selection.
    @ViewBuilder
    @MainActor private var branchRow: some View {
        let row = HStack(spacing: 0) {
            //
            // One cell is a small target, so the button is deliberately
            // wider than its glyph: the frame adds the blank cell after the
            // triangle, and the focus gutter contributes the two before it.
            // Four cells to hit, one glyph to read.
            //
            // Inside a list the triangle keeps that click target but stops
            // being FOCUSABLE: the row is the focusable there, Space is the
            // row's (it selects) and Return is the row's (it activates —
            // which for a branch means disclosing it). A second focus stop
            // in the row would take both keys with it.
            triangle

            content(element)
        }
        if rowOwnsFocus {
            row
        } else {
            _BehindContentTapModifier(content: row) {
                triangleFocused = true
                toggle()
            }
        }
    }

    /// The triangle: a Tab stop of its own when nothing else owns the row, a
    /// bare tappable glyph when a list's cursor does.
    @ViewBuilder
    @MainActor private var triangle: some View {
        let glyph = Text(verbatim: isExpanded
            ? TerminalSymbols.disclosureExpanded
            : TerminalSymbols.disclosureCollapsed)
            .frame(width: DisclosureMetrics.triangleColumnWidth)
        if rowOwnsFocus {
            // The same four cells, still clickable — the focus gutter is drawn
            // by the list's own cursor rather than by a button here, so the
            // glyph is padded to keep the column it had.
            glyph
                .padding(.leading, BorderRenderer.focusIndicatorWidth)
                .onTapGesture { toggle() }
        } else {
            Button(action: toggle, label: { glyph })
                .buttonStyle(.borderless)
                // Only when the triangle is the focus stop. Inside a list the
                // row is focusable and the LIST answers these keys, with the
                // whole ladder — recursive open on Option, and a Left that
                // walks out of the subtree before it gives up. Registering them
                // here as well would put two handlers on one keystroke.
                .buttonKeyExtras(keys: [.left, .right]) { event in
                    setExpanded(event.key == .right)
                }
                // So a click on the LABEL can move the keyboard here too — see
                // `branchRow`.
                .focused($triangleFocused)
        }
    }

    /// Opens a closed node, or closes an open one.
    @MainActor private func toggle() {
        setExpanded(!expansion.read().open.contains(id))
    }

    /// Puts this node into a named state, and reports whether that changed
    /// anything — which is what decides if the key was used up.
    @discardableResult
    @MainActor private func setExpanded(_ open: Bool) -> Bool {
        guard expansion.read().open.contains(id) != open else { return open }
        expansion.set(CollectionOfOne(id), open: open)
        return true
    }
}
extension _OutlineRow: View {}

// MARK: - Initializers (Identifiable)

extension OutlineGroup where Leaf: View, Data.Element: Identifiable, ID == Data.Element.ID {
    /// Creates an outline rooted at a single element.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - expansion: A binding to the set of open branches' IDs, for the app
    ///     to keep and to open and close branches from code; `nil` for the
    ///     outline to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on ``OutlineGroup``).
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ root: DataElement,
        children: KeyPath<DataElement, Data?>,
        expansion: Binding<Set<ID>>? = nil,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: [root], id: \.id, children: children, expansion: expansion, content: content)
    }

    /// Creates an outline from a collection of top-level elements.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - expansion: A binding to the set of open branches' IDs, for the app
    ///     to keep and to open and close branches from code; `nil` for the
    ///     outline to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on ``OutlineGroup``).
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ data: Data,
        children: KeyPath<DataElement, Data?>,
        expansion: Binding<Set<ID>>? = nil,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: Array(data), id: \.id, children: children, expansion: expansion, content: content)
    }
}

// MARK: - Initializers (explicit id)

extension OutlineGroup where Leaf: View {
    /// Creates an outline rooted at a single element, keyed by an explicit id.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - expansion: A binding to the set of open branches' IDs, for the app
    ///     to keep and to open and close branches from code; `nil` for the
    ///     outline to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on ``OutlineGroup``).
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ root: DataElement,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        expansion: Binding<Set<ID>>? = nil,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: [root], id: id, children: children, expansion: expansion, content: content)
    }

    /// Creates an outline from a collection of top-level elements, keyed by an
    /// explicit id.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - expansion: A binding to the set of open branches' IDs, for the app
    ///     to keep and to open and close branches from code; `nil` for the
    ///     outline to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on ``OutlineGroup``).
    ///   - content: Builds a node's label.
    public init<DataElement>(
        _ data: Data,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        expansion: Binding<Set<ID>>? = nil,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: Array(data), id: id, children: children, expansion: expansion, content: content)
    }
}

// MARK: - Storing it

extension OutlineGroup {
    /// The one designated initializer every public one funnels through, for
    /// views and for table rows alike.
    package init(
        roots: [Data.Element],
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<ID>>? = nil,
        content: @escaping (Data.Element) -> Leaf
    ) {
        self.roots = roots
        self.idKeyPath = id
        self.childrenKeyPath = children
        self.appExpansion = expansion
        self.content = content
    }
}

@MainActor extension _OutlineRow: OutlineRowMarking {}

@MainActor extension OutlineGroup: KeyedRowProvider where Leaf: View {
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        runs.append(.outline)
    }
}
