//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentedAgainCacheTests.swift
//
//  A page drawn behind a surface presented a second time draws what a page
//  with no render cache draws (PERFCASE-F13). A `List` under a popover put up
//  again kept its scrollbar column, and its rows a cell narrower, once the
//  focus went into the popover: its drawing was stored on the frame the
//  popover came back, while the focus had not yet landed anywhere and the list
//  answered "do I hold the focus" with what it last knew, and the Tab that
//  landed it moved the focus from nothing, which named no view to drop.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

@Observable
@MainActor
private final class PresentedAgainModel {
    var shown = false
    var amount = 20
    var level = 50.0
}

/// What the page presents over its list. Not private: the suite's test takes
/// it as an argument.
enum PresentedAgainSurface: String, CaseIterable, CustomTestStringConvertible {
    case popover, sheet, alert, confirmationDialog
    var testDescription: String { rawValue }
}

/// The surface's content: two value controls, as the perf case's popover has.
private struct PresentedValues: View {
    let model: PresentedAgainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Stepper("Amount", value: Binding(get: { model.amount }, set: { model.amount = $0 }), in: 0...100)
            Slider(value: Binding(get: { model.level }, set: { model.level = $0 }), in: 0...100, step: 1) {
                Text(verbatim: "Level")
            }
        }
    }
}

/// A row with its status pushed to the trailing edge, so a row drawn a cell
/// narrower shows it a cell to the left.
private struct PresentedAgainRow: View, Equatable {
    let index: Int

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "row \(index)")
            Spacer()
            Text(verbatim: index.isMultiple(of: 3) ? "active" : "queued")
        }
    }
}

/// The list, in a view of its own: a composite whose value never changes,
/// which a value memo serves whole while nothing it reads moves, as the perf
/// case's page part is.
private struct PresentedAgainList: View {
    var body: some View {
        List {
            ForEach(0..<60, id: \.self) { PresentedAgainRow(index: $0) }
        }
    }
}

/// A title the surface is presented from, over a list longer than the screen.
private struct PresentedAgainPage: View {
    let model: PresentedAgainModel
    let surface: PresentedAgainSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            presenting(Text(verbatim: "title"))
            PresentedAgainList()
        }
    }

    private var shown: Binding<Bool> { Binding(get: { model.shown }, set: { model.shown = $0 }) }

    @ViewBuilder
    private func presenting(_ title: Text) -> some View {
        switch surface {
        case .popover:
            title.popover(isPresented: shown) { PresentedValues(model: model) }
        case .sheet:
            title.sheet(isPresented: shown) { PresentedValues(model: model) }
        case .alert:
            title.alert(Text(verbatim: "Alert"), isPresented: shown) {
                Button("One") {}
                Button("Two") {}
                Button("Cancel", role: .cancel) {}
            }
        case .confirmationDialog:
            title.confirmationDialog(Text(verbatim: "Choose"), isPresented: shown) {
                Button("One") {}
                Button("Two") {}
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

@MainActor
@Suite("A page behind a surface presented again draws what an uncached page draws")
struct PresentedAgainCacheTests {
    /// The perf case's script, three times over: presented, Tab into it,
    /// Right three times, Escape; after every step the screen of an app with a
    /// render cache against one with its cache emptied before every frame.
    /// The steps whose screens differed.
    private func divergentSteps(_ surface: PresentedAgainSurface) -> [String] {
        let models = (warm: PresentedAgainModel(), cold: PresentedAgainModel())
        let warm = TestApp(width: 60, height: 16) { PresentedAgainPage(model: models.warm, surface: surface) }
        let cold = TestApp(width: 60, height: 16) { PresentedAgainPage(model: models.cold, surface: surface) }
        cold.clearsRenderCacheEachFrame = true
        // As a running app's cache, which keeps a subtree that takes real
        // time: here every subtree, whatever this machine's speed, so the
        // page's list is served whole, as the perf case's was.
        for app in [warm, cold] {
            app.renderCache.learnsFromTiming = true
            app.renderCache.plainMemo.heavySubtree = .zero
        }
        var divergent: [String] = []
        var now: Int64 = 0
        // One frame a step, as the session runner draws: the frame after the
        // presentation is the one that stores the page before the focus lands.
        func step(_ name: String, _ act: (TestApp, PresentedAgainModel) -> Void) {
            now += 16_666_667
            for (app, model) in [(warm, models.warm), (cold, models.cold)] {
                act(app, model)
                app.frame(atNanos: now)
            }
            if warm.screen.styledLines != cold.screen.styledLines { divergent.append(name) }
        }
        step("open") { _, _ in }
        step("settle") { _, _ in }
        for round in 1...3 {
            step("present \(round)") { _, model in model.shown = true }
            step("tab \(round)") { app, _ in app.send(KeyEvent(key: .tab)) }
            for press in 1...3 {
                step("right \(round).\(press)") { app, _ in app.send(KeyEvent(key: .right)) }
            }
            step("escape \(round)") { app, _ in app.send(KeyEvent(key: .escape)) }
        }
        return divergent
    }

    @Test(
        "Presented, dismissed and presented again, the page behind draws as an uncached page does",
        arguments: PresentedAgainSurface.allCases)
    func presentedAgain(_ surface: PresentedAgainSurface) {
        let divergent = divergentSteps(surface)
        #expect(divergent.isEmpty, "the cached page differed from the uncached one after \(divergent)")
    }
}
