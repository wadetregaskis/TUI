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
            InboxPage(inbox: inbox)
                .sheet(isPresented: Binding(get: { placement.presented }, set: { placement.presented = $0 })) {
                    InboxDetail(inbox: inbox)
                        .presentationDetents(
                            [.height(8), .medium, .large],
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
/// past it to `.large` — a modal — back down, dismissed, opened again by the
/// app, and back out to the list.
private enum DockedMove: CaseIterable {
    case into, grow, past, back, dismiss, reopen, out
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
        case .past: return SessionStep(action: "sheet-past", keys: [KeyEvent(key: .up)])
        case .back: return SessionStep(action: "sheet-back", keys: [KeyEvent(key: .down)])
        case .dismiss: return SessionStep(action: "sheet-dismiss", keys: [KeyEvent(key: .escape)])
        case .reopen:
            placement.detent = .height(8)
            placement.presented = true
            return SessionStep(action: "sheet-reopen")
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

    /// Whether `line` is the grabber's rule: a row of nothing but horizontal
    /// rule — the handle in its middle drawn in a heavier one — unlike a box's
    /// top or bottom border, which has corners.
    private static func isGrabberRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 8 && trimmed.allSatisfy { "─━═".contains($0) } && trimmed.contains { $0 != "─" }
    }
}
