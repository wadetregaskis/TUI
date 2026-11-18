//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseVocabulary.swift
//
//  The words a perf case is written in: what a page is built from, the
//  container around it, the terminal's size, the steps of its script, and the
//  complexity class its counts must keep. Written once; a case is one line of
//  a table that combines them (`CaseTable.swift`, design
//  `Documentation/Historical/Performance/A declarative perf-case table.md`,
//  B-PERFCASE-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - Compositions

/// A page a case can be built from on its own, by its name in the table.
///
/// A dotted name: the control, then the shape of it. Each is built over the
/// case's ``CaseRows`` by ``CaseCompositionView``.
enum CaseLeaf: String, CaseIterable, Sendable {
    /// A selectable `List` of the rows, one line each.
    case listPlain = "list.plain"
    /// The same list under `.searchable`, filtered by the app as the query is
    /// typed: a filter that is O(n) in the app's own code.
    case listSearch = "list.search"
    /// A selectable `Table` of five columns, every one `.width(.fit)`.
    case tableFit5 = "table.fit5"
    /// A `Table` of five columns, the last wrapping to up to three lines.
    case tableWrap5 = "table.wrap5"
    /// Variable-height messages in a `LazyVStack`, one to three lines each.
    case chatLazy = "chat.lazy"
    /// The same messages in an eager `VStack`.
    case chatEager = "chat.eager"
    /// A `TextEditor` over the rows as lines of text, wrapping.
    case editorWrap = "editor.wrap"
    /// A selectable `List(_:children:)` of the rows as a tree
    /// (``CaseRows/tree``): one root, a branch every
    /// ``CaseRows/outlineFanOut`` rows, the rest leaves.
    case outlineList = "outline.list"
    /// The same tree as a selectable `Table(_:children:)` of three columns.
    case outlineTable = "outline.table"
    /// The same table with the app keeping its expansion
    /// (`Table(_:children:expansion:)`, ``CaseRows/open``).
    case outlineBound = "outline.bound"
    /// The same, every branch open from the start: the app's set holds
    /// them all, as an app's tree that starts open does (tuitree's, after
    /// an Option-Right on its root).
    case outlineOpen = "outline.open"
    /// The same tree as a selectable `Table(of:columns:rows:)` of three
    /// columns whose rows are written as tuitree writes its own: a `ForEach`
    /// of a `DisclosureTableRow` for each branch, its rows built by the same
    /// row content again, and a `TableRow` for each leaf.
    case outlineRows = "outline.rows"
    /// The same tree as a selectable `List` of one `Section` holding an
    /// `OutlineGroup`.
    case outlineSection = "outline.section"
    /// `outline.list` with the app keeping its expansion
    /// (`List(_:children:expansion:)`, ``CaseRows/open``).
    case outlineListBound = "outline.list.bound"
    /// `outline.section` with the app keeping its expansion
    /// (`OutlineGroup(_:children:expansion:)`, ``CaseRows/open``).
    case outlineSectionBound = "outline.section.bound"
    /// A bare `OutlineGroup` as a `ScrollView`'s whole content, the shape its
    /// doc example uses, over the members of the tree's groups as its roots
    /// (``CaseRows/forest``): 18 of every 100 rows, half of them branches of
    /// nine leaves, all closed.
    case outlineScroll = "outline.scroll"

    // The controls (`CaseControlView`): pages whose rows are controls, or
    // whose count sits beside the controls a script drives.

    /// A `Grid` of the rows, four cells each: eager, every row laid out.
    case grid
    /// A `Form` in `.grouped` style: a section of a `Stepper`, a `Slider` and
    /// a `DatePicker`, then a section of a `Toggle` per row.
    case formGrouped = "form.grouped"
    /// The same form in `.columns` style.
    case formColumns = "form.columns"
    /// A `Button` per row in an eager `VStack`: what a Tab walks through.
    case controls
    /// A `Stepper`, a `Slider` and a `DatePicker` alone in a `VStack`; `n`
    /// draws nothing.
    case values
    /// A `Menu` of a `Button` per row, under a line of text.
    case menu
}

extension CaseLeaf {
    /// Whether the leaf shows the rows as a tree (``CaseRows/tree``).
    var isOutline: Bool {
        switch self {
        case .outlineList, .outlineTable, .outlineBound, .outlineOpen, .outlineRows, .outlineSection,
            .outlineListBound, .outlineSectionBound, .outlineScroll:
            true
        default: false
        }
    }

    /// Whether the leaf is one of the controls `CaseControlView` draws.
    var isControl: Bool {
        switch self {
        case .grid, .formGrouped, .formColumns, .controls, .values, .menu: true
        default: false
        }
    }
}

/// What a case's page is built from: a leaf, leaves combined, or a `Stress`
/// scenario adopted as it is.
indirect enum CaseComposition: Equatable, Sendable, CustomStringConvertible {
    case leaf(CaseLeaf)
    /// A `TabView` with one tab per part, the first selected.
    case tabs([Self])
    /// An `HSplitView` of two parts.
    case split(Self, Self)
    /// The page in a scene whose focus follows the pointer
    /// (`.focusFollowsPointer(true)`): `follows(<composition>)`. A scene's
    /// setting, so it wraps a whole page, never a part of one. Without it a
    /// hover moves no focus and no list's cursor row, as in an app that has
    /// not turned it on (HOVER-FOCUS b).
    case followsPointer(Self)
    /// An existing scenario, or one variant of a matrix scenario, built as
    /// `--bench` builds it: `stress:<scenario>[/<variant>]`. Its `n` is the
    /// scenario's `--scale`.
    case adopted(scenario: String, variant: String?)
    /// The first part with `.sheet(isPresented:)` presenting the second,
    /// bound to ``CaseRows/presented``: `sheet(a,b)`.
    case sheet(Self, Self)
    /// The first part with `.sheet(item:)` presenting the second for
    /// ``CaseRows/item``, under a line naming the item: `sheetitem(a,b)`.
    /// Each item's content keeps its own state while the sheet is up (W17).
    case sheetItem(Self, Self)
    /// The first part under a line of title that a `.popover(isPresented:)`
    /// holding the second is attached to: `popover(a,b)`.
    case popover(Self, Self)
    /// The part with an `.alert(_:isPresented:)` of two buttons and a
    /// message, bound to ``CaseRows/presented``: `alert(a)`.
    case alert(Self)
    /// A `NavigationSplitView` of two columns or three: `nsplit(a,b)`,
    /// `nsplit(a,b,c)`.
    case navigationSplit([Self])

    var description: String {
        switch self {
        case .leaf(let leaf): leaf.rawValue
        case .tabs(let parts): "tabs(\(parts.map(\.description).joined(separator: ",")))"
        case .split(let first, let second): "split(\(first),\(second))"
        case .followsPointer(let page): "follows(\(page))"
        case .adopted(let scenario, let variant): "stress:\(scenario)" + (variant.map { "/\($0)" } ?? "")
        case .sheet(let first, let second): "sheet(\(first),\(second))"
        case .sheetItem(let first, let second): "sheetitem(\(first),\(second))"
        case .popover(let first, let second): "popover(\(first),\(second))"
        case .alert(let page): "alert(\(page))"
        case .navigationSplit(let parts): "nsplit(\(parts.map(\.description).joined(separator: ",")))"
        }
    }

    /// The compositions this one is made of: none for a leaf or an adopted
    /// scenario.
    var parts: [Self] {
        switch self {
        case .leaf, .adopted: []
        case .tabs(let parts), .navigationSplit(let parts): parts
        case .split(let first, let second), .sheet(let first, let second), .sheetItem(let first, let second),
            .popover(let first, let second):
            [first, second]
        case .followsPointer(let page), .alert(let page): [page]
        }
    }

    /// Whether this is an adopted scenario, which brings its own container.
    var isAdopted: Bool {
        if case .adopted = self { return true }
        return false
    }

    /// Whether any part of the page shows the rows' text in a `TextEditor`.
    var hasEditor: Bool {
        if case .leaf(let leaf) = self { return leaf == .editorWrap }
        return parts.contains(where: \.hasEditor)
    }

    /// Whether the page's scene has the focus follow the pointer.
    var followsPointer: Bool {
        if case .followsPointer = self { return true }
        return false
    }

    /// The page without its scene's setting: what is drawn. Built without
    /// the wrapper, so a case that turns the setting on draws the same views
    /// as one that does not, and their counts differ only by what it does.
    var page: Self {
        if case .followsPointer(let page) = self { return page }
        return self
    }

    /// Whether any part of the page shows the rows as a tree.
    var hasOutline: Bool {
        if case .leaf(let leaf) = self { return leaf.isOutline }
        return parts.contains(where: \.hasOutline)
    }

    /// Whether the page's tree starts with every branch open
    /// (``CaseLeaf/outlineOpen``).
    var opensTree: Bool {
        if case .leaf(let leaf) = self { return leaf == .outlineOpen }
        return parts.contains(where: \.opensTree)
    }
}

// MARK: - Containers

/// What a case's composition sits in. A superset of the SCROLL-FIT
/// baseline's situations (`ScrollFitSituation` in `TUIIntegrationTests`),
/// whose subjects and situations are the seed of this vocabulary; folding the
/// two together waits until SCROLL-FIT has landed (design, "What stays as it
/// is").
enum CaseContainer: String, CaseIterable, Sendable {
    /// The composition is the whole page.
    case alone
    /// In a `ScrollView`, under a line of title: `ScrollView { VStack { title; it } }`.
    case title
    /// In a bottom-anchored `ScrollView`, as a conversation is followed.
    case bottom
    /// In a sheet presented over a line of text.
    case sheet
    /// Under a title in a `VStack` fixed to its ideal height.
    case fixed
    /// Under a line of title in a `VStack` that fills the page, as an app's
    /// page holds its table: the stack measures it before it is drawn.
    case stacked
    /// None: an adopted scenario brings its own.
    case none = "-"
}

// MARK: - Sizes

/// A terminal size, in cells: `80x24`.
struct CaseSize: Equatable, Sendable, CustomStringConvertible {
    let width: Int
    let height: Int

    /// The size `text` names, or `nil` for one that names none or a size too
    /// small to draw anything in.
    init?(_ text: some StringProtocol) {
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width >= 4, height >= 2
        else { return nil }
        self.width = width
        self.height = height
    }

    var description: String { "\(width)x\(height)" }
}

// MARK: - Script steps

/// A key a script can press, by its name in the table.
enum CaseKey: String, CaseIterable, Sendable {
    case pgdn, pgup, end, home, up, down, left, right, tab, enter, space, esc, bksp
    /// Option-Right and Option-Left: an outline's open and close of a whole
    /// subtree.
    case oright, oleft
    /// Find (⌃F, ⌘F's stand-in): puts the keyboard in a `.searchable` field,
    /// which leaves the first focus to the content — a typed key there is the
    /// list's type select, not a query.
    case find

    /// The event the key sends.
    var event: KeyEvent {
        switch self {
        case .pgdn: KeyEvent(key: .pageDown)
        case .pgup: KeyEvent(key: .pageUp)
        case .end: KeyEvent(key: .end)
        case .home: KeyEvent(key: .home)
        case .up: KeyEvent(key: .up)
        case .down: KeyEvent(key: .down)
        case .left: KeyEvent(key: .left)
        case .right: KeyEvent(key: .right)
        case .tab: KeyEvent(key: .tab)
        case .enter: KeyEvent(key: .enter)
        case .space: KeyEvent(key: .space)
        case .esc: KeyEvent(key: .escape)
        case .bksp: KeyEvent(key: .backspace)
        case .oright: KeyEvent(key: .right, alt: true)
        case .oleft: KeyEvent(key: .left, alt: true)
        case .find: KeyEvent(key: .character("f"), ctrl: true)
        }
    }
}

/// One step of a case's script, named after `TestApp`'s methods so a test's
/// author already knows them. Every step ends in the frames it causes.
enum CaseStep: Equatable, Sendable, CustomStringConvertible {
    /// The first frame. Always the first phase, and only that.
    case open
    /// A frame with nothing changed.
    case idle
    /// `scroll(.down/.up, by: k)` over the screen's middle: positive is down.
    case wheel(Int)
    /// `press(_:)`.
    case key(CaseKey)
    /// `type(_:)`: a character, then its frames, then the next.
    case type(String)
    /// The pointer moved by `k` rows: positive is down.
    case hover(Int)
    /// `resize(width:height:)`.
    case resize(CaseSize)
    /// `resize(width:height:)` by a change in each, as a window dragged at
    /// its corner resizes a terminal: `resize:-8x-3`. Clamped to 4x2.
    case resizeBy(width: Int, height: Int)
    /// `advance(by:)`, in milliseconds.
    case tick(Int)
    /// `k` rows appended to the case's model, outside any render.
    case append(Int)
    /// The middle row's content changed.
    case editMiddle
    /// The row at an index removed.
    case remove(Int)
    /// The row at one index moved to another.
    case move(from: Int, to: Int)
    /// Every row replaced by new content, the same count of them.
    case replace
    /// ``CaseRows/presented`` set: the sheet, popover or alert bound to it
    /// presented, as an app's button sets its flag.
    case present
    /// ``CaseRows/presented`` cleared and ``CaseRows/item`` set to `nil`.
    case dismiss
    /// ``CaseRows/item`` set to the row at an index (clamped): an item sheet
    /// presented for it, or switched to it.
    case item(Int)
    /// ``CaseRows/item`` moved on by `k` rows (clamped), from the row before
    /// the first when there is none: `item:+k`, a walk through the items.
    case nextItem(Int)

    /// The step as the table spells it.
    var description: String {
        switch self {
        case .open: "open"
        case .idle: "idle"
        case .wheel(let ticks): "wheel:\(ticks < 0 ? "-" : "+")\(abs(ticks))"
        case .key(let key): "key:\(key.rawValue)"
        case .type(let text): "type:\(text)"
        case .hover(let rows): "hover:\(rows < 0 ? "-" : "+")\(abs(rows))"
        case .resize(let size): "resize:\(size)"
        case .resizeBy(let width, let height):
            "resize:\(width < 0 ? "-" : "+")\(abs(width))x\(height < 0 ? "-" : "+")\(abs(height))"
        case .tick(let milliseconds): "tick:\(milliseconds)"
        case .append(let count): "append:\(count)"
        case .editMiddle: "edit:mid"
        case .remove(let index): "remove:\(index)"
        case .move(let from, let to): "move:\(from)>\(to)"
        case .replace: "replace"
        case .present: "present"
        case .dismiss: "dismiss"
        case .item(let index): "item:\(index)"
        case .nextItem(let rows): "item:+\(rows)"
        }
    }
}

/// A step and how many times in a row it is taken: one phase of a script,
/// counted on its own, since a first frame and a keystroke are different
/// frames.
struct CasePhase: Equatable, Sendable {
    let step: CaseStep
    let repeats: Int

    /// The phase as the table spells it: `wheel:+5*20`.
    var spelling: String { repeats == 1 ? step.description : "\(step)*\(repeats)" }
}

// MARK: - Scaling

/// The complexity class a case's counts must keep, checked by playing the
/// case again at a larger `n` (B-PERFCASE-7).
enum CaseScaling: String, CaseIterable, Sendable {
    /// The counts at 10n equal the counts at n: every one is O(1).
    case flat
    /// Each count at 2n is the count at n or twice it, ±10%: every one is O(1)
    /// or O(n). Not "every count doubles": a case's chrome and its first
    /// frame's fixed work do not.
    case linear
    /// Not checked.
    case none = "-"

    /// What `n` is multiplied by for the second run, or `nil` for none.
    var factor: Int? {
        switch self {
        case .flat: 10
        case .linear: 2
        case .none: nil
        }
    }
}

// MARK: - Tags

/// The words a case's tags are drawn from: what it exercises, for picking a
/// subset by tag. A listed set, so a misspelt tag is an error in the table
/// rather than a case no `--tags` ever picks; a new word is added here.
enum CaseTags {
    static let known: Set<String> = [
        "anchor", "appshape", "bytes", "eager", "editor", "hover", "invalidate", "lazy", "list", "memo",
        "narrow", "offscreen", "outline", "resize", "scroll", "search", "sheet", "split", "table", "tabs",
        "tail", "window", "wrap",
        "alert", "focus", "form", "grid", "menu", "navigation", "popover", "storm", "tiny", "typing", "values",
    ]
}

// MARK: - A case

/// One row of the perf-case table.
struct PerfCase: Sendable {
    /// Stable and kebab-case; what `--case` names.
    let id: String
    let composition: CaseComposition
    let container: CaseContainer
    let size: CaseSize
    /// The data count, synthesised from the case's seed (``CaseRows``), or an
    /// adopted scenario's `--scale`.
    let count: Int
    /// The script, its first phase `open`.
    let phases: [CasePhase]
    let scaling: CaseScaling
    /// Whether the timed sweep includes it.
    let timed: Bool
    let tags: [String]
    /// Where the row is written, for an error about it.
    let origin: CaseOrigin
}

/// A place in a case table's source: a file and a line in it.
struct CaseOrigin: Sendable, CustomStringConvertible {
    let file: String
    let line: Int

    var description: String { "\(file):\(line)" }
}
