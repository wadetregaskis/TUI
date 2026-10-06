//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetDetentTests.swift
//
//  A detented sheet: the heights it can rest at, which one it rests at, and
//  where it rests — on the bottom edge of the content area.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Sheet detents")
struct SheetDetentTests {

    private struct Detented: PresentationDetentsProviding {
        let detents: Set<PresentationDetent>
        var detentSelection: Binding<PresentationDetent>?
    }

    private func context(width: Int = 40, height: Int = 20) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, _ in
            environment.mouseEventDispatcher = MouseEventDispatcher()
            environment.terminalWidth = width
            environment.overlayContentHeight = height
        }
    }

    // MARK: - Stops

    @Test("Detents that floor to one height on a short terminal are one stop, smallest first")
    func collidingDetentsAreOneStop() {
        let sheet = Detented(detents: [.large, .height(5), .medium, .fraction(0.5)])
        let stops = sheet.stops(in: 10, environment: EnvironmentValues())
        #expect(stops.map(\.height) == [5, 10], "\(stops)")
        // Of the three that make 5 rows, one stands for it by a fixed order,
        // whatever the set's.
        #expect(stops.first?.detent == .medium)
        #expect(stops.last?.detent == .large)
    }

    @Test("Where the sheet rests: the selection's height, else the kept detent, else the smallest")
    func restingStop() {
        let environment = EnvironmentValues()
        let unbound = Detented(detents: [.large, .medium, .height(3)])
        let stops = unbound.stops(in: 20, environment: environment)
        #expect(stops.map(\.height) == [3, 10, 20])
        #expect(unbound.restingIndex(among: stops, chosen: nil, extent: 20, environment: environment) == 0)
        #expect(unbound.restingIndex(among: stops, chosen: .large, extent: 20, environment: environment) == 2)
        // A kept detent the content no longer offers is passed over.
        #expect(unbound.restingIndex(among: stops, chosen: .fraction(0.9), extent: 20, environment: environment) == 0)

        let bound = Detented(detents: [.large, .medium, .height(3)], detentSelection: .constant(.medium))
        #expect(
            bound.restingIndex(among: stops, chosen: .large, extent: 20, environment: environment) == 1,
            "the binding wins over a kept detent")
        // Two detents of one height: the selection rests at the height, even
        // though the other detent stands for it.
        let colliding = Detented(detents: [.medium, .height(5), .large], detentSelection: .constant(.height(5)))
        let shortStops = colliding.stops(in: 10, environment: environment)
        #expect(colliding.restingIndex(among: shortStops, chosen: nil, extent: 10, environment: environment) == 0)
    }

    // MARK: - Placement

    @Test("A detented sheet rests on the bottom edge, centred across it, and is not dragged by its border")
    func detentedSheetDocks() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("t") { Text("x") }.presentationDetents([.height(6), .large])
            },
            context: context())
        let layer = buffer.overlays[0]
        #expect(layer.isDockedAtBottom)
        #expect(layer.content.hitTestRegions.isEmpty, "no drag regions on its border: \(layer.content.hitTestRegions)")
        let placed = layer.placed(maxWidth: 40, maxHeight: 20)
        #expect(placed.y == 14, "flush on the bottom edge: \(placed.y)")
        #expect(placed.x == (40 - layer.content.width) / 2)
    }

    @Test("A sheet with no detents stays centred and draggable")
    func undetentedSheetStaysCentred() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { Panel("t") { Text("x") } },
            context: context())
        let layer = buffer.overlays[0]
        #expect(!layer.isDockedAtBottom)
        #expect(layer.offsetY == 0)
        #expect(!layer.content.hitTestRegions.isEmpty, "the title row and border drag it")
    }

    @Test("A cover takes no detent and is not docked")
    func coverIgnoresDetents() {
        let buffer = renderToBuffer(
            Text("page").fullScreenCover(isPresented: .constant(true)) {
                Text("cover").presentationDetents([.medium])
            },
            context: context())
        #expect(!buffer.overlays[0].isDockedAtBottom)
        #expect(buffer.overlays[0].content.height == 20)
    }
}
