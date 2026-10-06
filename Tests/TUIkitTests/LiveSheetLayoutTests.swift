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

@MainActor
@Suite("A live sheet's page is laid out above it", .rendersEnglishUI)
struct LiveSheetLayoutTests {
    private static let frameNanos: Int64 = 16_666_667

    private func rows(_ app: HeadlessApp<DockedApp>) -> [String] {
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

    @Test("A terminal too short to leave the page three rows presents the sheet as a modal")
    func shortTerminalIsAModal() {
        let model = LiveSheetModel()
        let app = HeadlessApp(DockedApp(model: model), width: 40, height: 8)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 8") }, "the page was laid out short: \(rows(app))")
    }
}
