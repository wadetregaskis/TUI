//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveSheetDockHoldTests.swift
//
//  A live sheet whose dock pushed its presenter out of a lazy window is held
//  off the dock as a modal (decisions-D7S B-D7S-5) — and only that one: a
//  presenter that posted nothing for any other reason keeps docking.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the pages below switch for a frame and back, by reference so the
/// binding a frame built reaches it.
@MainActor
private final class HoldModel {
    var busy = false
    var showsPage = true
    var busyBinding: Binding<Bool> { Binding(get: { self.busy }, set: { self.busy = $0 }) }
}

/// The review's input: a page with a save button, a live sheet over it, and a
/// `.modal` the save presents while it runs — drawing the page and the sheet's
/// presenter into the modal's backdrop, where the presenter posts no dock.
private struct BusyPageApp: App {
    let model: HoldModel

    init() { model = HoldModel() }

    init(model: HoldModel) { self.model = model }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("Save") { model.busy = true }
                GeometryReader { proxy in Text("page height \(proxy.size.height)") }
            }
            .sheet(isPresented: .constant(true)) {
                Panel("Live") { Text("x") }
                    .presentationDetents([.height(8), .large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackgroundInteraction(.enabled)
            }
            .modal(isPresented: model.busyBinding) { Text("Saving…") }
        }
    }
}

/// A page presenting a live sheet, behind a branch the app switches away from
/// for a frame and back — as a tab or a navigation destination is.
private struct SwitchedPageApp: App {
    let model: HoldModel

    init() { model = HoldModel() }

    init(model: HoldModel) { self.model = model }

    var body: some Scene {
        WindowGroup {
            if model.showsPage {
                GeometryReader { proxy in Text("page height \(proxy.size.height)") }
                    .sheet(isPresented: .constant(true)) {
                        Panel("Live") { Text("x") }
                            .presentationDetents([.height(8), .large])
                            .presentationDragIndicator(.hidden)
                            .presentationBackgroundInteraction(.enabled)
                    }
            } else {
                Text("elsewhere")
            }
        }
    }
}

@MainActor
@Suite("A live sheet is held off the dock only when its dock pushed its presenter out", .rendersEnglishUI)
struct LiveSheetDockHoldTests {
    private static let frameNanos: Int64 = 16_666_667

    private func rows(_ app: HeadlessApp<some App>) -> [String] {
        app.screen.map(\.stripped)
    }

    /// Drawn into the modal's backdrop, the presenter posted no dock, and the
    /// frame after — the modal gone, the presenter drawn again — took that
    /// for its row having left a lazy window: the sheet was a modal for the
    /// rest of its presentation, the page dimmed and the focus pulled into it.
    @Test("A presenter drawn into a modal's backdrop for a frame keeps its sheet docked")
    func backdropFrameDoesNotHoldTheSheet() {
        let model = HoldModel()
        let app = HeadlessApp(BusyPageApp(model: model), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        // 20 rows, 8 docked, the button's 1: the reader's 11.
        #expect(rows(app).contains { $0.contains("page height 11") }, "precondition: docked: \(rows(app))")
        model.busy = true
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(rows(app).contains { $0.contains("Saving") }, "precondition: the modal is up: \(rows(app))")
        // The save finished before the next frame.
        model.busy = false
        var now = 3 * Self.frameNanos
        for _ in 0..<3 {
            app.frame(atNanos: now)
            now += Self.frameNanos
        }
        #expect(
            rows(app).contains { $0.contains("page height 11") },
            "the sheet is held off the dock after one frame behind a modal: \(rows(app))")
    }

    /// The same for a presenter not drawn at all for a frame: its page
    /// switched away and back, which says nothing about whether docking
    /// pushes it out.
    @Test("A presenter away for a frame with its page keeps its sheet docked")
    func pageAwayForAFrameDoesNotHoldTheSheet() {
        let model = HoldModel()
        let app = HeadlessApp(SwitchedPageApp(model: model), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frameNanos)
        #expect(rows(app).contains { $0.contains("page height 12") }, "precondition: docked: \(rows(app))")
        model.showsPage = false
        app.frame(atNanos: 2 * Self.frameNanos)
        #expect(rows(app).contains { $0.contains("elsewhere") }, "precondition: the page is away")
        model.showsPage = true
        var now = 3 * Self.frameNanos
        for _ in 0..<3 {
            app.frame(atNanos: now)
            now += Self.frameNanos
        }
        #expect(
            rows(app).contains { $0.contains("page height 12") },
            "the sheet is held off the dock after its page was away for a frame: \(rows(app))")
    }
}
