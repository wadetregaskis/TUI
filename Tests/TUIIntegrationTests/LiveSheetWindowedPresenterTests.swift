//  🖥️ TUI — A Terminal UI framework for Swift
//  LiveSheetWindowedPresenterTests.swift
//
//  A live sheet is held off the dock when its own dock left its presenter's
//  row out of a lazy container's window (decisions-D7S B-D7S-5) — asked of
//  the presenter's ROW in the walk drawn, not of its ancestry: a presenter
//  below a drawn `List` or lazy stack that drew nothing for any other reason
//  keeps docking.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What the pages below switch for a frame and back, by reference so the
/// binding a frame built reaches it.
@MainActor
private final class WindowedHoldModel {
    var showsPage = true
    var expanded = true
    var presented = false
    var expandedBinding: Binding<Bool> { Binding(get: { self.expanded }, set: { self.expanded = $0 }) }
    var presentedBinding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
}

/// The live sheet every page below presents: docked eight rows high, the page
/// usable beside it. The modifiers are the sheet content's own, not a body's:
/// the presentation reads them off the content it is handed.
@MainActor
private func livePanel() -> some View {
    Panel("Live") { Text("x") }
        .presentationDetents([.height(8), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
}

/// Where a page's presenter is, below a container that windows its rows.
private enum Host {
    /// The review's input: a `List` whose content is an `if`/`else`.
    case listBranch
    /// The same inside a lazy stack in a scroll view.
    case lazyStackBranch
    /// A disclosure group in a `List`, collapsed for a frame and opened again.
    case listDisclosure
}

/// A page whose presenter the app takes away for a frame — a branch switched,
/// a group collapsed — under a `List` or a lazy stack that is drawn all the
/// while, with the page's height on its first row.
private struct BranchPageApp: App {
    let model: WindowedHoldModel
    let host: Host

    init() { (model, host) = (WindowedHoldModel(), .listBranch) }

    init(model: WindowedHoldModel, host: Host) { (self.model, self.host) = (model, host) }

    var body: some Scene {
        WindowGroup {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Text("page height \(proxy.size.height)")
                    page
                }
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch host {
        case .listBranch:
            List {
                if model.showsPage {
                    Text("row").sheet(isPresented: .constant(true)) { livePanel() }
                } else {
                    Text("elsewhere")
                }
            }
        case .lazyStackBranch:
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.showsPage {
                        Text("row").sheet(isPresented: .constant(true)) { livePanel() }
                    } else {
                        Text("elsewhere")
                    }
                }
            }
        case .listDisclosure:
            List {
                DisclosureGroup("Group", isExpanded: model.expandedBinding) {
                    Text("row").sheet(isPresented: .constant(true)) { livePanel() }
                }
            }
        }
    }
}

/// A row of a container that windows its rows, presenting a live sheet: a
/// row inside the window at the full height and outside it at the height the
/// docked sheet leaves.
private enum RowHost {
    /// A lazy stack of one-line rows, windowed by arithmetic (the uniform
    /// window).
    case uniformLazyStack
    /// A short lazy stack whose rows are not all one height, walked whole
    /// (the exact slot walk).
    case mixedLazyStack
    /// A long one, filled outward from an anchor (the anchored window).
    case longMixedLazyStack
    /// A `Table` whose cell presents it.
    case table
    /// A long lazy stack of one-line rows glued to its bottom, presenting
    /// from a row in the top rows of the viewport: on the frame the dock
    /// shortens the page, the scroll view draws its content once at the
    /// offset it had, the presenter among it, and again at the new tail,
    /// without it (`coverSnappedViewport`), in one walk.
    case bottomGluedLazyStack

    /// The row that presents: row 15 of one-line rows, row 12 where every
    /// fourth row is two lines tall — line 15 either way; line 2 of the 20
    /// a glued stack shows of its 200.
    var presenter: Int {
        switch self {
        case .uniformLazyStack, .table: 15
        case .mixedLazyStack, .longMixedLazyStack: 12
        case .bottomGluedLazyStack: 182
        }
    }
}

/// A row-hosted sheet's identifiable item, for the `Table`.
private struct Item: Identifiable {
    let id: Int
}

private struct RowHostedApp: App {
    let model: WindowedHoldModel
    let host: RowHost

    init() { (model, host) = (WindowedHoldModel(), .uniformLazyStack) }

    init(model: WindowedHoldModel, host: RowHost) { (self.model, self.host) = (model, host) }

    var body: some Scene {
        WindowGroup {
            switch host {
            case .uniformLazyStack, .mixedLazyStack, .longMixedLazyStack:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<(host == .longMixedLazyStack ? 600 : 30), id: \.self) { index in
                            Text(host != .uniformLazyStack && index.isMultiple(of: 4) ? "row \(index)\n…" : "row \(index)")
                                .sheet(isPresented: presented(index)) { livePanel() }
                        }
                    }
                }
            case .bottomGluedLazyStack:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<200, id: \.self) { index in
                            Text("row \(index)").sheet(isPresented: presented(index)) { livePanel() }
                        }
                    }
                }
                .defaultScrollAnchor(.bottom)
            case .table:
                Table((0..<30).map { Item(id: $0) }) {
                    TableColumn("Row") { (item: Item) in
                        Text("row \(item.id)").sheet(isPresented: presented(item.id)) { livePanel() }
                    }
                }
            }
        }
    }

    private func presented(_ row: Int) -> Binding<Bool> {
        row == host.presenter ? model.presentedBinding : .constant(false)
    }
}

@MainActor
@Suite("A live sheet is held off the dock only when its dock left its presenter's row out of a window", .rendersEnglishUI)
struct LiveSheetWindowedPresenterTests {
    private static let frameNanos: Int64 = 16_666_667

    private func rows(_ app: HeadlessApp<some App>) -> [String] {
        app.screen.map(\.stripped)
    }

    /// The presenter drew nothing on the frame it was away, below a `List`
    /// (or a lazy stack) drawn on that frame — and the rule asked only that:
    /// not drawn, below a container that windows its rows. It never asked
    /// whether the container left the presenter out of its window, so the
    /// sheet was a modal from the frame the presenter came back, for the
    /// rest of its presentation.
    @Test(
        "A presenter away for a frame below a drawn List or lazy stack keeps its sheet docked",
        arguments: [Host.listBranch, .lazyStackBranch, .listDisclosure])
    fileprivate func awayBelowAWindowingContainer(host: Host) {
        let model = WindowedHoldModel()
        let app = HeadlessApp(BranchPageApp(model: model, host: host), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        // 20 rows, 8 docked: the page's 12.
        #expect(rows(app).contains { $0.contains("page height 12") }, "precondition: docked: \(rows(app))")
        model.showsPage = false
        model.expanded = false
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(!rows(app).contains { $0.contains("Live") }, "precondition: the presenter is away: \(rows(app))")
        model.showsPage = true
        model.expanded = true
        var now = 3 * Self.frameNanos
        for _ in 0..<3 {
            app.frame(atNanos: now)
            now += Self.frameNanos
        }
        #expect(
            rows(app).contains { $0.contains("page height 12") },
            "the sheet is held off the dock after its presenter was away for a frame: \(rows(app))")
    }

    /// Each windowing container says which of its rows it drew; a row the
    /// dock pushes out of the window still holds the sheet off the dock, so
    /// the page and the sheet stop alternating.
    @Test(
        "A sheet whose dock pushes its row out of a lazy stack's or a table's window settles as a modal",
        arguments: [RowHost.uniformLazyStack, .mixedLazyStack, .longMixedLazyStack, .table, .bottomGluedLazyStack])
    fileprivate func rowHostedSheetDoesNotLoop(host: RowHost) {
        let model = WindowedHoldModel()
        let app = HeadlessApp(RowHostedApp(model: model, host: host), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(
            rows(app).contains { $0.contains("row \(host.presenter)") },
            "precondition: the row is in the window: \(rows(app))")
        model.presented = true
        var now = 2 * Self.frameNanos
        app.frame(atNanos: now)
        var drawn = [rows(app).contains { $0.contains("Live") }]
        for _ in 0..<8 {
            guard let wake = app.nextWake(after: now) else { break }
            now = max(wake, now + 1)
            app.frame(atNanos: now)
            drawn.append(rows(app).contains { $0.contains("Live") })
        }
        #expect(app.nextWake(after: now) == nil, "the page and the sheet are still alternating: \(drawn)")
        #expect(drawn.last == true, "the sheet is not drawn: \(drawn)")
        app.frame(atNanos: now + Self.frameNanos)
        #expect(rows(app).contains { $0.contains("Live") }, "the sheet went again: \(rows(app))")
    }

    /// One frame of a dock, by the hooks the run loop and the chrome host
    /// call: walked once per entry of `drawsPresenter` — a `.global`
    /// reader's correction walks twice — with the presenter's row drawn or
    /// left out of its list's window in each walk. Returns what the
    /// presenter, in each walk it was drawn, was told about its dock.
    private func frame(
        _ drawsPresenter: [Bool], focus: FocusManager, storage: StateStorage
    ) -> [Bool] {
        let list = ViewIdentity(path: "App/List")
        let presenter = ViewIdentity(path: "App/List/Row[5]/Sheet")
        focus.beginRenderPass()
        storage.beginRenderPass()
        var told: [Bool] = []
        for draws in drawsPresenter {
            storage.beginSceneRender()
            focus.beginSceneRender()
            let dock = focus.presentationDock(in: 20, storage: storage)
            storage.noteWindowedRows(
                WindowedRows(root: list, row: { $0 == presenter ? 5 : nil }, isDrawn: { _ in draws }))
            if draws {
                // What a presented sheet's presenter does wherever it draws.
                storage.markActive(presenter)
                told.append(focus.presenterWentUndrawnUnderItsDock("sheet"))
                focus.notePresentationDock(id: "sheet", presenter: presenter) { _ in 8 }
            }
            _ = focus.settlePresentationDock(laidOutBy: dock, in: 20, storage: storage)
        }
        return told
    }

    /// A frame a `.global` reader corrects is walked twice, and only the
    /// second walk is drawn. The rule asked whether the presenter had drawn
    /// anything all PASS — so one the discarded walk drew and the drawn walk
    /// left out of the window read as drawn, and the loop went unchecked —
    /// and it noted its verdict after EACH walk, so a frame after it that
    /// drew the presenter in its second walk alone asked after the first
    /// walk had overwritten what the frame before had noted.
    @Test("The presenter's row is asked of the walk drawn, and the frame after asks in every walk")
    func twoWalkFramesAskTheDrawnWalk() {
        let focus = FocusManager()
        let storage = StateStorage()
        #expect(frame([true], focus: focus, storage: storage) == [false], "precondition: drawn and posting")
        // Docked: the discarded walk draws the row, the drawn walk leaves it
        // out of the window.
        #expect(frame([true, false], focus: focus, storage: storage) == [false])
        // Not docked: the row comes back in the second walk only.
        #expect(
            frame([false, true], focus: focus, storage: storage) == [true],
            "the presenter its dock pushed out was not told so")
        // And a frame after that one is told nothing.
        #expect(frame([true], focus: focus, storage: storage) == [false])
    }
}
