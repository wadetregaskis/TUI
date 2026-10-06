//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveSheetLayoutTests.swift
//
//  A live sheet docks at the bottom of the content area and the page is laid
//  out in the rows above it — through the real render loop, whose root asks
//  the dock ledger before the walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A page that says the height it was laid out at, under a live sheet.
private struct DockedPage: View {
    let model: LiveSheetModel
    var interaction: PresentationBackgroundInteraction = .enabled

    var body: some View {
        GeometryReader { proxy in
            Text("page height \(proxy.size.height)")
        }
        .sheet(isPresented: model.presentedBinding) {
            Panel("Sheet") { Text("sheet body") }
                .presentationDetents([.height(6), .large], selection: model.detentBinding)
                .presentationBackgroundInteraction(interaction)
        }
    }
}

private struct DockedApp: App {
    let model: LiveSheetModel
    let interaction: PresentationBackgroundInteraction

    init() {
        model = LiveSheetModel()
        interaction = .enabled
    }

    init(model: LiveSheetModel, interaction: PresentationBackgroundInteraction = .enabled) {
        self.model = model
        self.interaction = interaction
    }

    var body: some Scene {
        WindowGroup { DockedPage(model: model, interaction: interaction) }
    }
}

/// What the window toolbar's live sheet is presented for, by reference so the
/// binding a frame built reaches it.
@MainActor
private final class ToolbarSheetModel {
    var note: LiveNote?
    var binding: Binding<LiveNote?> { Binding(get: { self.note }, set: { self.note = $0 }) }
}

/// A page under a window toolbar whose item presents a live `item:` sheet —
/// nothing in it takes the focus, so nothing breathes and asks for frames.
private struct ToolbarDockApp: App {
    let model: ToolbarSheetModel

    init() { model = ToolbarSheetModel() }

    init(model: ToolbarSheetModel) { self.model = model }

    var body: some Scene {
        WindowGroup {
            GeometryReader { proxy in
                Text("page height \(proxy.size.height)")
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text("tools").sheet(item: model.binding) { note in
                        Text("note \(note.id)").border()
                            .presentationDetents([.height(6)])
                            .presentationBackgroundInteraction(.enabled)
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("A live sheet's page is laid out above it", .rendersEnglishUI)
struct LiveSheetLayoutTests {
    private static let frameNanos: Int64 = 16_666_667

    private func rows(_ app: HeadlessApp<some App>) -> [String] {
        app.screen.map(\.stripped)
    }

    @Test("A sheet presented from the start is docked under the page from its second frame")
    func dockedUnderThePage() {
        let model = LiveSheetModel()
        let app = HeadlessApp(DockedApp(model: model), width: 40, height: 20)
        app.frame(atNanos: 0)
        #expect(app.nextWake(after: 0) != nil, "the dock learnt on the first frame asked for no second")
        app.frame(atNanos: Self.frameNanos)
        let screen = rows(app)
        #expect(screen.contains { $0.contains("page height 14") }, "\(screen)")
        // The grabber's rule on the row under the page, the panel's title
        // below it.
        #expect(screen[14].contains("─"), "the sheet does not start on the row under the page: \(screen)")
        #expect(screen.firstIndex { $0.contains("Sheet") } == 15, "\(screen)")
        #expect(screen[19].contains("╰") || screen[19].contains("└"), "the sheet's foot is not the last row: \(screen)")
    }

    @Test("A sheet the app presents between frames is docked on the first frame it is drawn")
    func appDrivenOpenIsNotLate() {
        let model = LiveSheetModel()
        model.presented = false
        let app = HeadlessApp(DockedApp(model: model), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 20") }, "precondition: no sheet")
        model.presented = true
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 14") }, "\(rows(app))")
        // The pulse of the focus the sheet took is what asks for frames now;
        // a late dock would show as the page drawn at 20 under the sheet.
        model.presented = false
        app.frame(atNanos: 3 * Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 20") }, "dismissed, the page took its rows back late")
    }

    @Test("Above its upThrough detent the sheet is a modal over the whole page")
    func grownPastUpThroughIsAModal() {
        let model = LiveSheetModel()
        let app = HeadlessApp(
            DockedApp(model: model, interaction: .enabled(upThrough: .height(6))), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 14") }, "precondition: docked")
        model.detent = .large
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(!rows(app).contains { $0.contains("page height 14") }, "the grown sheet is still docked")
        #expect(rows(app)[0].contains("─"), "the grown sheet does not cover the content area: \(rows(app))")
    }

    /// The window's toolbars are drawn after the root compares the dock it
    /// laid the page out by with the docks the walk posted, so a sheet
    /// presented from a toolbar item posted its dock too late to be compared:
    /// learnt late — an `item:` sheet's content is unknown until it opens —
    /// it asked for no frame, and the page stayed at its full height under
    /// the sheet until something else drew one.
    @Test("A live sheet learnt late from a window toolbar item asks for the frame that docks it")
    func toolbarSheetLearntLateSettles() throws {
        let model = ToolbarSheetModel()
        let app = HeadlessApp(ToolbarDockApp(model: model), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        let full = try #require(rows(app).first { $0.contains("page height") }, "\(rows(app))")
        #expect(app.nextWake(after: Self.frameNanos) == nil, "precondition: an idle page")
        model.note = LiveNote(id: 1)
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(rows(app).contains { $0.contains("note 1") }, "precondition: the sheet is drawn")
        let wake = try #require(app.nextWake(after: 2 * Self.frameNanos), "the late dock asked for no frame")
        app.frame(atNanos: wake)
        let docked = try #require(rows(app).first { $0.contains("page height") })
        #expect(docked != full, "the page was not laid out above the sheet: \(rows(app))")
    }

    @Test("A terminal too short to leave the page three rows presents the sheet as a modal")
    func shortTerminalIsAModal() {
        let model = LiveSheetModel()
        let app = HeadlessApp(DockedApp(model: model), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 8") }, "the page was laid out short: \(rows(app))")
    }
}
