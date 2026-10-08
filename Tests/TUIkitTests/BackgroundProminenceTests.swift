//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackgroundProminenceTests.swift
//
//  `\.backgroundProminence`: a `List` raises it for the content of its focused,
//  selected row, and the content styles resolve to the palette's own text
//  tiers under a raised background.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation

/// A row that says which prominence its content was rendered under.
private struct ProminenceProbe: View {
    let name: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text("\(name):\(prominence == .increased ? "raised" : "plain")")
    }
}

/// The selection a live app would keep in `@State`, as a reference the test
/// can change between frames.
@MainActor
private final class SelectionModel {
    var selection: String?
}

@MainActor
@Suite("Background prominence")
struct BackgroundProminenceTests {
    private let tuiContext = TUIContext()
    private let focusManager = FocusManager()
    private let model = SelectionModel()

    private var list: some View {
        let model = self.model
        return List(
            selection: Binding(get: { model.selection }, set: { model.selection = $0 })
        ) {
            ForEach(["alpha", "beta", "gamma"], id: \.self) { ProminenceProbe(name: $0) }
        }
    }

    /// One live-loop-shaped frame with a persistent focus manager and cache.
    private func renderFrame() -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tuiContext)
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let lines = renderToBuffer(list, context: context).lines.map(\.stripped)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return lines
    }

    /// What the row named `name` said about its background.
    private func state(of name: String, in lines: [String]) -> String? {
        for line in lines {
            if let range = line.range(of: "\(name):") {
                return String(line[range.upperBound...].prefix { $0.isLetter })
            }
        }
        return nil
    }

    @Test("The focused, selected row renders raised; the others plain")
    func focusedSelectedRowIsRaised() {
        model.selection = "alpha"
        _ = renderFrame()
        let lines = renderFrame()
        #expect(state(of: "alpha", in: lines) == "raised", "\(lines)")
        #expect(state(of: "beta", in: lines) == "plain", "\(lines)")
        #expect(state(of: "gamma", in: lines) == "plain", "\(lines)")
    }

    @Test("An unselected cursor row is not raised")
    func unselectedCursorRowIsPlain() {
        model.selection = nil
        _ = renderFrame()
        let lines = renderFrame()
        #expect(state(of: "alpha", in: lines) == "plain", "\(lines)")
    }

    @Test("A selected row away from the cursor is not raised")
    func selectionAwayFromTheCursorIsPlain() {
        model.selection = "beta"
        _ = renderFrame()
        let lines = renderFrame()
        #expect(state(of: "alpha", in: lines) == "plain", "\(lines)")
        #expect(state(of: "beta", in: lines) == "plain", "\(lines)")
    }

    @Test("A row that stops being raised renders plain again, not from its cached raised render")
    func loweringClearsTheRowsCachedRender() {
        model.selection = "alpha"
        _ = renderFrame()
        #expect(state(of: "alpha", in: renderFrame()) == "raised")
        model.selection = nil
        let lowered = renderFrame()
        #expect(state(of: "alpha", in: lowered) == "plain", "\(lowered) sel=\(String(describing: model.selection))")
        model.selection = "alpha"
        let raisedAgain = renderFrame()
        #expect(state(of: "alpha", in: raisedAgain) == "raised", "\(raisedAgain)")
    }

    @Test("Under a raised background the content levels are the palette's tiers, whatever style is inherited")
    func levelsResolveToThePaletteTiers() {
        var environment = EnvironmentValues()
        environment.foregroundStyle = .color(.red)
        let palette = environment.palette
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) != Paint.color(palette.foregroundSecondary))
        environment.backgroundProminence = .increased
        #expect(HierarchicalShapeStyle.primary.paint(in: environment) == Paint.color(palette.foreground))
        #expect(HierarchicalShapeStyle.secondary.paint(in: environment) == Paint.color(palette.foregroundSecondary))
        #expect(HierarchicalShapeStyle.tertiary.paint(in: environment) == Paint.color(palette.foregroundTertiary))
    }

    @Test("The environment value defaults to .standard")
    func defaultIsStandard() {
        #expect(EnvironmentValues().backgroundProminence == .standard)
        #expect(BackgroundProminence.increased != .standard)
    }
}

/// A table row for the table suite.
private struct ProbeRow: Identifiable {
    let id: String
}

@MainActor
@Suite("Background prominence in a table")
struct TableBackgroundProminenceTests {
    private let tuiContext = TUIContext()
    private let focusManager = FocusManager()
    private let model = SelectionModel()
    private let rows = ["alpha", "beta", "gamma"].map(ProbeRow.init)

    private func table(lineLimit: Int) -> some View {
        let model = self.model
        return Table(
            rows, selection: Binding(get: { model.selection }, set: { model.selection = $0 })
        ) {
            TableColumn("Name") { (row: ProbeRow) in ProminenceProbe(name: row.id) }
                .width(20).lineLimit(lineLimit)
        }
    }

    private func renderFrame(lineLimit: Int) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tuiContext)
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let lines = renderToBuffer(table(lineLimit: lineLimit), context: context).lines.map(\.stripped)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return lines
    }

    private func state(of name: String, in lines: [String]) -> String? {
        for line in lines {
            if let range = line.range(of: "\(name):") {
                return String(line[range.upperBound...].prefix { $0.isLetter })
            }
        }
        return nil
    }

    @Test("The focused, selected row's view cells render raised, on both row paths", arguments: [1, 2])
    func focusedSelectedRowIsRaised(lineLimit: Int) {
        model.selection = "alpha"
        _ = renderFrame(lineLimit: lineLimit)
        let lines = renderFrame(lineLimit: lineLimit)
        #expect(state(of: "alpha", in: lines) == "raised", "\(lines)")
        #expect(state(of: "beta", in: lines) == "plain", "\(lines)")
    }

    @Test("A row that stops being raised renders plain again", arguments: [1, 2])
    func loweringRendersPlain(lineLimit: Int) {
        model.selection = "alpha"
        _ = renderFrame(lineLimit: lineLimit)
        #expect(state(of: "alpha", in: renderFrame(lineLimit: lineLimit)) == "raised")
        model.selection = nil
        let lowered = renderFrame(lineLimit: lineLimit)
        #expect(state(of: "alpha", in: lowered) == "plain", "\(lowered)")
    }
}
