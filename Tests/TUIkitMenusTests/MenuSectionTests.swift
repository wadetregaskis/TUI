//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuSectionTests.swift
//
//  A `Section` in a menu, as SwiftUI's macOS menus draw one (measured on
//  macOS 15.8, `Tools/SwiftUIProbes/Sections and subview counting/menuapp.swift`:
//  SwiftUI's own `NSMenu` read back): set
//  off by separators — none at the menu's top or bottom, never two in a row —
//  under its header as a section-header title, which is no item. Until then
//  a section in a menu was its parts (decisions B16): its header a line of
//  plain text among the items, nothing between the sections.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkitApp
@testable import TUIkitFoundation
import TUIkitMenus
@testable import TUIkitTestSupport

/// Which item ran.
@MainActor
private final class Chosen {
    var name: String?
}

@MainActor
@Suite("A section in a menu")
struct MenuSectionTests {

    private func harness(width: Int = 30, height: Int = 20) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        context.environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @ViewBuilder
    private func items(_ chosen: Chosen) -> some View {
        Button("Loose") { chosen.name = "Loose" }
        Section("First") {
            Button("Apple") { chosen.name = "Apple" }
            Button("Pear") { chosen.name = "Pear" }
        }
        Section("Second") {
            Button("Leek") { chosen.name = "Leek" }
        }
    }

    /// The menu's rows, inside its border, each trimmed: a separator reads as
    /// `-`.
    private func rows(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.dropFirst().dropLast().map(\.stripped)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "│ ")) }
            .filter { !$0.isEmpty }
            .map { $0.allSatisfy { $0 == "─" } ? "-" : $0 }
    }

    @Test("An inline menu sets each section off with separators, under its header")
    func inlineSections() {
        let (tui, context) = harness()
        let view = Menu("Food") { items(Chosen()) }.menuStyle(.inline)
        let drawn = rows(renderArmed(view, tui: tui, context: context))
        // The heading and its rule, then the items: one separator between the
        // loose item and the first section, one between the sections, none at
        // the end.
        #expect(drawn == ["Food", "-", "Loose", "-", "First", "Apple", "Pear", "-", "Second", "Leek"], "\(drawn)")
    }

    @Test("A pop-up menu sets each section off with separators, its header styled and no item")
    func popUpSections() throws {
        let (tui, context) = harness()
        let chosen = Chosen()
        let view = Menu("Food") { items(chosen) }
        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        let popup = try #require(renderArmed(view, tui: tui, context: context).overlays.first).content
        #expect(rows(popup) == ["Loose", "-", "First", "Apple", "Pear", "-", "Second", "Leek"], "\(rows(popup))")
        // The header is drawn as a List's section header is: bold and dimmed.
        let header = try #require(popup.lines.first { $0.stripped.contains("First") })
        #expect(header.contains("\u{1B}[1;2;"), "\(header.debugDescription)")
    }

    @Test("A section that leads the menu adds no separator above it, and the keyboard steps over its header")
    func leadingSectionAndKeyboard() throws {
        let (tui, context) = harness()
        let chosen = Chosen()
        let view = Menu("Food") {
            Section("First") { Button("Apple") { chosen.name = "Apple" } }
            Divider()
            Section("Second") { Button("Leek") { chosen.name = "Leek" } }
            Button("Tail") { chosen.name = "Tail" }
        }
        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        let popup = try #require(renderArmed(view, tui: tui, context: context).overlays.first).content
        // The app's own divider stands for the separator between the sections.
        #expect(rows(popup) == ["First", "Apple", "-", "Second", "Leek", "-", "Tail"], "\(rows(popup))")
        // From the last row, two Ups reach Apple: the header and the
        // separators between are no rows.
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .end)))
        _ = renderArmed(view, tui: tui, context: context)
        for _ in 0..<2 {
            #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .up)))
            _ = renderArmed(view, tui: tui, context: context)
        }
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .enter)))
        #expect(chosen.name == "Apple", "chose \(chosen.name ?? "nothing")")
    }
}
