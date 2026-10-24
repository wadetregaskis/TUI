//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerFaceTests.swift
//
//  A pop-up picker's closed control is a bordered button's face
//  (`ControlFace`): it follows the appearance, the control size and the
//  border shape as a button does, and its menu opens under all of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitPickers
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("A pop-up picker's face")
struct PickerFaceTests {

    private func picker() -> some View {
        Picker("Fruit", selection: .constant("a")) {
            Text("Apple").tag("a")
            Text("Banana").tag("b")
        }
        .pickerStyle(.menu)
    }

    @Test("It is drawn as a button is, in the controls' family")
    func followsTheAppearance() {
        let context = makeRenderContext(width: 40, height: 8)
        let drawn = renderToBuffer(picker(), context: context)
        let lines = drawn.lines.map(\.stripped)
        // Padded to "Banana", the widest option, as its menu is.
        #expect(lines[0].contains("▐ Apple  ▾ ▌"), "the default, the solid family's caps: \(lines)")
        let solid = renderToBuffer(picker().appearance(.block), context: context).lines.map(\.stripped)
        #expect(solid[0].contains("▐ Apple  ▾ ▌"), "the solid family's caps: \(solid)")
        let outline = renderToBuffer(picker().controlStyle(.lines), context: context).lines.map(\.stripped)
        #expect(outline[0].contains("( Apple  ▾ )"), "the lines family's capsule: \(outline)")
        let measured = measureChild(picker(), proposal: .unspecified, context: context)
        #expect(measured.width == drawn.width, "measure and render agree")
    }

    @Test("At a large control size it is three rows, and its menu opens under all three")
    func largeFaceAnchorsTheMenu() throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = picker().controlSize(.large)
        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            return buffer
        }
        let closed = frame()
        #expect(closed.height == 3, "a large face is three rows: \(closed.lines.map(\.stripped))")
        let measured = measureChild(view, proposal: .unspecified, context: makeRenderContext(width: 40, height: 12))
        #expect(measured.height == 3, "and measures three")
        let id = try #require(focusManager.registeredFocusIDsInActiveSection().first { $0.hasPrefix("picker-") })
        focusManager.focus(id: id)
        _ = frame()
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .enter)), "Return opens it")
        let opened = frame()
        let menu = try #require(opened.overlays.first, "the menu is open")
        #expect(menu.offsetY == 3 && menu.anchorHeight == 3, "under the whole face: \(menu.offsetY), \(menu.anchorHeight)")
    }
}
