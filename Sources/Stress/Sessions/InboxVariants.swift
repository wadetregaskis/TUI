//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InboxVariants.swift
//
//  The inbox, put where a value-trusting memo (Option C) has to draw its rows
//  again, or cannot tell whether it must: under a tint that moves, on a pushed
//  screen, in a sheet, and with its selection bound through `@Bindable`. The
//  same script plays against the same data as `inbox`, so each variant's
//  counts and costs read against `inbox`'s: what C keeps of inbox's saving
//  in each place is the difference. The pushed screen does not type into the
//  search field: its search steps are quiet, as many as `inbox`'s and making
//  the same draws, so its other steps are `inbox`'s step for step.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - Where the inbox is put

/// Where the inbox is put, and how its selection is bound.
enum InboxVariant: String, CaseIterable {
    /// Under a `.tint` that the session flips now and then: an environment
    /// write above every row, which C compares and must draw the rows again
    /// for.
    case tinted = "inbox-tinted"
    /// Pushed onto a `NavigationStack`, so every row is drawn under the pushed
    /// screen's dismiss action, which C cannot compare until its box lands.
    case pushed = "inbox-pushed"
    /// Presented in a sheet, so every row is drawn under the sheet's dismiss
    /// action, which C cannot compare until its box lands.
    case sheet = "inbox-sheet"
    /// The selection bound through `@Bindable` to the model, as an app binds
    /// an `@Observable`'s property: the list reads it through a `Binding`,
    /// which nothing observes today.
    case observable = "inbox-observable"
    /// Beside a live sheet docked under it, which shows the selected item
    /// (A19, design C): the page is laid out in the rows the sheet leaves, at
    /// every height the sheet moves to, and every so often the script goes
    /// into the sheet, grows it past its `upThrough` into a modal and back,
    /// dismisses it and opens it again.
    case docked = "inbox-docked"

    /// What the variant does to the inbox, for `--sessions`.
    var summary: String {
        switch self {
        case .tinted: "under a .tint the session flips"
        case .pushed: "pushed onto a NavigationStack"
        case .sheet: "presented in a sheet"
        case .observable: "its selection bound through @Bindable"
        case .docked: "beside a live sheet docked under it, grown past its threshold and back"
        }
    }
}

/// Where the variant's inbox sits: what the pushed screen or the sheet is
/// over, and what flips the tint.
@Observable
@MainActor
final class InboxPlacement {
    /// What is pushed over the root: the inbox, once. A `String`, so the
    /// destination is not the list's own selection type.
    var path: [String] = []
    /// Whether the sheet holding the inbox is presented.
    var presented = false
    /// Which of two tints the inbox is under.
    var tinted = false
    /// The detent the docked sheet rests at.
    var detent: PresentationDetent = .height(8)
    /// How many times a key only the page answers (F5) reached it.
    var pageKeys = 0
}

/// The inbox page, put where `variant` puts it.
struct InboxVariantPage: View {
    let inbox: Inbox
    let placement: InboxPlacement
    let variant: InboxVariant

    var body: some View {
        switch variant {
        case .tinted:
            InboxPage(inbox: inbox).tint(placement.tinted ? Color.orange : Color.cyan)
        case .pushed:
            NavigationStack(path: Binding(get: { placement.path }, set: { placement.path = $0 })) {
                Text(verbatim: "Inbox").navigationDestination(for: String.self) { _ in InboxPage(inbox: inbox) }
            }
        case .sheet:
            Text(verbatim: "Inbox")
                .sheet(isPresented: Binding(get: { placement.presented }, set: { placement.presented = $0 })) {
                    InboxPage(inbox: inbox)
                }
        case .observable:
            InboxPage(inbox: inbox, bindsThroughBindable: true)
        case .docked:
            // F5 is the page's own key: heard wherever the focus is while the
            // page is live, and never while a modal holds it.
            InboxPage(inbox: inbox)
                .onKeyEvent(.f5) { placement.pageKeys += 1 }
                .sheet(isPresented: Binding(get: { placement.presented }, set: { placement.presented = $0 })) {
                    InboxDetail(inbox: inbox)
                        // `.fraction(0.75)` past the threshold, where the sheet
                        // is a modal and the page still shows above it, dimmed.
                        .presentationDetents(
                            [.height(8), .medium, .fraction(0.75), .large],
                            selection: Binding(get: { placement.detent }, set: { placement.detent = $0 }))
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
        }
    }
}

/// The docked sheet's content: the selected item, in a box the sheet's band
/// gives its size.
private struct InboxDetail: View {
    let inbox: Inbox

    var body: some View {
        let selected = inbox.items.first { $0.id == inbox.selection }
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Selected: \(selected?.title ?? "nothing")")
            Text(verbatim: selected.map { "Tag: \($0.tag)" } ?? "")
        }
        .border()
    }
}

// MARK: - The script

/// `inbox`'s script, played against the inbox where `variant` puts it: opened
/// there before the first frame, and, under a tint, the tint flipped every
/// so often.
@MainActor
final class InboxVariantSession: StressSession {
    private let inbox: InboxSession
    private let placement = InboxPlacement()
    private let variant: InboxVariant

    init(config: StressConfig, variant: InboxVariant) {
        self.variant = variant
        inbox = InboxSession(config: config)
        inbox.countsAnywhere = variant == .pushed || variant == .sheet
        // The docked sheet's grabber is in the Tab cycle after the list, so
        // the search's Tab out of the field lands elsewhere: left out, as the
        // pushed screen's crumb bar leaves it out.
        inbox.searches = variant != .pushed && variant != .docked
        placement.path = variant == .pushed ? ["inbox"] : []
        placement.presented = variant == .sheet || variant == .docked
    }

    /// The docked sheet's interlude still to play, one move a step.
    private var dockedMoves: [DockedMove] = []

    /// The interlude's move the last step made, if it made one.
    private var lastDockedMove: DockedMove?

    /// How many times the page's own key had reached it before the step that
    /// pressed it — `nil` on any other step.
    private var pageKeysBeforeStep: Int?

    /// What the last step was, and the selection before its keys: a select
    /// that moved the selection reached the list, whose cursor row is then on
    /// the screen.
    private var lastAction = ""
    private var selectionBeforeStep: Int?

    /// The size of the screen the last check saw: a select played with a
    /// resize has its cursor row revealed in the list's OLD viewport, which
    /// the resize then cuts — the list's own business, not the sheet's.
    private var lastCheckedSize: (rows: Int, columns: Int)?

    var page: InboxVariantPage { InboxVariantPage(inbox: inbox.inbox, placement: placement, variant: variant) }

    /// `inbox`'s step; under a tint, every 23rd flips the tint as well, a
    /// write outside any event, as a theme following the time of day is.
    func step(_ index: Int) -> SessionStep {
        selectionBeforeStep = inbox.inbox.selection
        if variant == .docked, let step = dockedStep(index) {
            lastAction = step.action
            return step
        }
        var step = inbox.step(index)
        lastAction = step.action
        if variant == .tinted, index > 0, index.isMultiple(of: 23) {
            placement.tinted.toggle()
            step.action += "+tint"
        }
        return step
    }

    func check(_ screen: [String], after index: Int) -> String? {
        variant == .docked ? dockedCheck(screen, after: index) : inbox.check(screen, after: index)
    }

    func check(styled screen: [String], after index: Int) -> String? {
        variant == .docked ? dockedStyledCheck(screen, after: index) : nil
    }

    /// The docked variant's frames are drawn in 24 bits, its styled checks
    /// reading the colours the palette states; the others at whatever the
    /// process detected.
    var colorDepth: ColorDepth? { variant == .docked ? .truecolor : nil }

    static func descriptor(_ variant: InboxVariant) -> SessionDescriptor {
        SessionDescriptor(
            id: variant.rawValue,
            summary: "the inbox, \(variant.summary)",
            exercises:
                "inbox's script against inbox's data, with the list where a value-trusting memo must draw "
                + "its rows again or cannot tell: what it keeps of inbox's saving there",
            make: { config, width, height, cold in
                DrivenSession(
                    InboxVariantSession(config: config, variant: variant), width: width, height: height, cold: cold)
            })
    }
}

// MARK: - The docked sheet

/// One move of the docked sheet's interlude: into the sheet, up to `.medium`,
/// the page's own key, past `.medium` to `.fraction(0.75)` — a modal — the
/// page's key again, back down, dismissed, a frame with no input, opened again
/// by the app, another frame with no input, and back out to the list.
private enum DockedMove: CaseIterable {
    case into, grow, pageKeyLive, past, pageKeyPast, back, dismiss, settleDismissed, reopen, settleReopened, out

    /// Whether the move moves the focus between the panes by presenting or
    /// dismissing the sheet: its frame is drawn before the focus it gives
    /// out is painted (`dockedStyledCheck`).
    var handsTheFocusOver: Bool { self == .dismiss || self == .reopen }
}

extension InboxVariantSession {
    /// The docked variant's step, where it is not `inbox`'s: its first, which
    /// leaves the sheet that took the focus as it was presented for the list,
    /// and, every 29th, the sheet's interlude, a move a step.
    fileprivate func dockedStep(_ index: Int) -> SessionStep? {
        if index == 0 {
            return SessionStep(action: "focus", keys: [KeyEvent(key: .tab, shift: true)])
        }
        if dockedMoves.isEmpty, index.isMultiple(of: 29) { dockedMoves = DockedMove.allCases }
        guard !dockedMoves.isEmpty else {
            lastDockedMove = nil
            return nil
        }
        let move = dockedMoves.removeFirst()
        lastDockedMove = move
        switch move {
        case .into: return SessionStep(action: "sheet-in", keys: [KeyEvent(key: .tab)])
        case .grow: return SessionStep(action: "sheet-grow", keys: [KeyEvent(key: .up)])
        case .pageKeyLive, .pageKeyPast:
            pageKeysBeforeStep = placement.pageKeys
            return SessionStep(action: "page-key", keys: [KeyEvent(key: .f5)])
        case .past: return SessionStep(action: "sheet-past", keys: [KeyEvent(key: .up)])
        case .back: return SessionStep(action: "sheet-back", keys: [KeyEvent(key: .down)])
        case .dismiss: return SessionStep(action: "sheet-dismiss", keys: [KeyEvent(key: .escape)])
        case .reopen:
            placement.detent = .height(8)
            placement.presented = true
            return SessionStep(action: "sheet-reopen")
        case .settleDismissed, .settleReopened: return SessionStep(action: "quiet")
        case .out: return SessionStep(action: "sheet-out", keys: [KeyEvent(key: .tab, shift: true)])
        }
    }

    /// The docked variant's checks, on top of `inbox`'s counts:
    ///
    /// - the page is laid out ABOVE the sheet, never under it: the counts are
    ///   over the grabber's rule, and the row a select moved the list's cursor
    ///   to is on the screen above it, where the reader can see it — the
    ///   reflow's whole promise (owner Q1), which a page laid out at its full
    ///   height under the sheet, as on the frame a dock is learnt late, breaks
    ///   as soon as the cursor walks into the rows the sheet covers;
    /// - a sheet that covers the content area (past its `upThrough`) leaves
    ///   nothing of the page to check; a dismissed one leaves no rule.
    fileprivate func dockedCheck(_ screen: [String], after index: Int) -> String? {
        let size = (rows: screen.count, columns: screen.first?.count ?? 0)
        let resized = lastCheckedSize.map { $0 != size } ?? false
        lastCheckedSize = size
        let rule = screen.firstIndex(where: Self.isGrabberRule)
        guard placement.presented else {
            if rule != nil { return "a dismissed sheet's grabber is still drawn" }
            return inbox.check(screen, after: index)
        }
        // No grabber: a terminal too short for two heights. Covering the
        // content area: past `upThrough`.
        if let problem = pageKeyProblem(screen, rule: rule) { return problem }
        guard let rule, rule > 0 else { return rule == nil ? inbox.check(screen, after: index) : nil }
        let page = Array(screen[..<rule])
        if let problem = inbox.check(page, after: index) { return "\(problem) above the sheet" }
        guard lastAction == "select", !resized, let id = inbox.inbox.selection, id != selectionBeforeStep,
            let item = inbox.inbox.items.first(where: { $0.id == id })
        else { return nil }
        let prefix = String(item.title.prefix(10))
        let marks = ["[ ] " + prefix, "[x] " + prefix]
        return page.contains { line in marks.contains { line.contains($0) } }
            ? nil : "the list's cursor row (\(prefix)…) is not above the sheet"
    }

    /// The page's own key (F5) reaches the page while it is live, and does
    /// nothing while the sheet is a modal over it — past its `upThrough`, or
    /// where a short terminal leaves no room to dock — as the frame's
    /// geometry says (``DockedGeometry``).
    private func pageKeyProblem(_ screen: [String], rule: Int?) -> String? {
        guard lastDockedMove == .pageKeyLive || lastDockedMove == .pageKeyPast,
            let before = pageKeysBeforeStep
        else { return nil }
        pageKeysBeforeStep = nil
        let heard = placement.pageKeys > before
        let geometry = rule.map { DockedGeometry(screen: screen, rule: $0) }
        let isModal = geometry?.isModal ?? false
        if isModal, heard { return "the page's key reached the page under the sheet past its threshold" }
        if !isModal, !heard { return "the page's key did not reach the live page beside the sheet" }
        return nil
    }

    /// The docked variant's checks of how the frame is painted:
    ///
    /// - one pane shows the focus, the one the status bar's items say holds
    ///   it — the sheet's "⎋ dismiss" shows only while the focus is in the
    ///   sheet. In the sheet, the grabber's handle is lit (its only focus
    ///   stop) and no row of the list breathes; on the page, the handle is
    ///   not lit. (The list's cursor need not be on the screen: a list that
    ///   does not hold the focus does not keep it in view as the page is
    ///   laid out short, and a resize cuts the viewport it was revealed in.)
    /// - past the threshold the page above the sheet is dimmed, every inked
    ///   cell of it; at or below it, it is not.
    ///
    /// Not on the frames that present the sheet again and dismiss it, which
    /// are drawn before the focus they hand over is painted. Presenting, the
    /// page is drawn before the presenter takes the focus into the sheet as
    /// it enters, so the list's cursor is still lit beside the handle;
    /// dismissing, the focus comes back to the list at the end of the pass,
    /// and the list reveals its cursor — which an unfocused list, laid out
    /// short, need not have kept in view — on the next. Each focus change
    /// asks for that next frame, which the `settle…` moves draw and this
    /// checks like any other.
    fileprivate func dockedStyledCheck(_ screen: [String], after index: Int) -> String? {
        guard lastDockedMove?.handsTheFocusOver != true else { return nil }
        let lines = screen.map(\.stripped)
        let cells = ScreenCells(screen)
        let rule = placement.presented ? lines.firstIndex(where: Self.isGrabberRule) : nil
        let geometry = rule.map { DockedGeometry(screen: lines, rule: $0) }
        let pageRows = 0..<(rule ?? lines.count)
        let handleLit = rule.map { Self.isHandleLit(cells.rows[$0]) } ?? false
        let cursorShown = listShowsItsCursor(lines, cells, in: pageRows)
        let focusInSheet = DockedGeometry.statusLine(of: lines)?.contains("⎋") == true
        if handleLit, cursorShown { return "both panes show the focus: the grabber's handle and the list's cursor" }
        if focusInSheet, !handleLit { return "the focus is in the sheet, and its grabber's handle is not lit" }
        if !focusInSheet, handleLit { return "the focus is on the page, and the sheet's grabber's handle is lit" }
        guard let geometry, let rule, rule > 0 else { return nil }
        let inked = pageRows.flatMap { cells.rows[$0] }.filter(\.hasInk)
        guard !inked.isEmpty else { return nil }
        let dimmed = inked.allSatisfy(\.isDim)
        if geometry.isModal, !dimmed { return "past its threshold the sheet leaves the page above it undimmed" }
        if !geometry.isModal, dimmed { return "the page beside the live sheet is dimmed" }
        return nil
    }

    /// Whether the rule's handle — its heavier middle run — is drawn in
    /// another ink than the rule: lit by the focus. (At rest it is the
    /// rule's own ink in the palette this session draws in; the pointer,
    /// which also lights it, is never moved here.)
    private static func isHandleLit(_ row: [ScreenCell]) -> Bool {
        guard let rest = row.first(where: { $0.character == "─" })?.foreground,
            let handle = row.first(where: { $0.character != nil && $0.character != "─" && $0.hasInk })
        else { return false }
        return ScreenCell.name(handle.foreground) != ScreenCell.name(rest)
    }

    /// Whether a row of the list in `rows` breathes the focus: a row on a
    /// field that is neither the page's (the list's most common) nor, for
    /// the selected row, the tint a selection rests in while the list does
    /// not hold the focus.
    private func listShowsItsCursor(_ lines: [String], _ cells: ScreenCells, in rows: Range<Int>) -> Bool {
        var fields: [(row: Int, field: String, selected: Bool)] = []
        for y in rows where lines[y].hasPrefix("│") && (lines[y].contains("[ ]") || lines[y].contains("[x]")) {
            fields.append((y, ScreenCell.name(cells.cell(row: y, column: 3)?.background), lines[y].contains("│●")))
        }
        let counts = Dictionary(fields.map { ($0.field, 1) }, uniquingKeysWith: +)
        guard let page = counts.max(by: { $0.value < $1.value })?.key else { return false }
        let tint = ColorDepth.withCurrent(.truecolor) { SystemPalette(.green).selectedRowFill() }
        let tintName = if case .fill(let colour) = tint { ScreenCell.name(colour) } else { "" }
        return fields.contains { $0.field != page && !($0.selected && $0.field == tintName) }
    }

    /// Whether `line` is the grabber's rule: a row of nothing but horizontal
    /// rule — the handle in its middle drawn in a heavier one — unlike a box's
    /// top or bottom border, which has corners.
    private static func isGrabberRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 8 && trimmed.allSatisfy { "─━═".contains($0) } && trimmed.contains { $0 != "─" }
    }
}

/// Where a docked frame puts the sheet, and so whether TUIkit must draw it as
/// a modal: the content area is the frame less the status bar's box, the
/// sheet runs from its rule to the content area's foot, and it docks live
/// only at or below `.medium` (its `upThrough`) and with three rows or more
/// for both it and the page — `LiveSheet.dock`'s rule, in rows.
private struct DockedGeometry {
    let isModal: Bool

    init(screen: [String], rule: Int) {
        let extent = Self.statusLine(of: screen) == nil ? screen.count : screen.count - 3
        let sheet = extent - rule
        isModal = sheet > extent / 2 || sheet < 3 || extent - sheet < 3
    }

    /// The status bar's line, where the frame ends in its box.
    static func statusLine(of screen: [String]) -> String? {
        guard screen.count >= 3, screen[screen.count - 3].hasPrefix("╭"), screen[screen.count - 1].hasPrefix("╰")
        else { return nil }
        return screen[screen.count - 2]
    }
}
