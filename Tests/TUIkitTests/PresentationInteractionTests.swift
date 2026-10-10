//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationInteractionTests.swift
//
//  `presentationBackgroundInteraction(_:)` and
//  `presentationContentInteraction(_:)` in the values that describe what a
//  presentation does by default: the page behind a sheet cannot be reached,
//  and an over-tall sheet scrolls inside its height rather than growing. The
//  live page's twin of the first is LiveSheetTests.backgroundIsLive; the
//  wheel's resizing is SheetWheelResizeTests'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Presentation interaction", .rendersEnglishUI)
struct PresentationInteractionTests {
    /// Counts the page's button.
    private final class Count {
        var value = 0
    }

    @Test("With background interaction disabled, the page behind a sheet takes neither keys nor clicks")
    func backgroundIsInert() {
        let harness = InputChainHarness(width: 40, height: 12)
        let pressed = Count()
        let page = {
            VStack {
                Button("Page") { pressed.value += 1 }
                Spacer()
            }
            .sheet(isPresented: .constant(true)) {
                Dialog(title: "Sheet") { Button("Inside") {} }
                    .presentationBackgroundInteraction(.disabled)
                    .presentationBackgroundInteraction(.automatic)
            }
        }
        harness.frame(page())
        harness.frame(page())
        for _ in 0..<3 {
            harness.press(KeyEvent(key: .tab))
            harness.frame(page())
            harness.press(KeyEvent(key: .enter))
            harness.frame(page())
        }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        harness.frame(page())
        #expect(pressed.value == 0)
    }

    @Test("Content that scrolls keeps an over-tall sheet inside the screen rather than growing it")
    func contentScrolls() {
        let harness = InputChainHarness(width: 40, height: 10)
        let page = {
            Text("page").sheet(isPresented: .constant(true)) {
                Dialog(title: "Long") {
                    VStack { ForEach(0..<30) { Text("row \($0)") } }
                }
                .presentationContentInteraction(.scrolls)
            }
        }
        harness.frame(page())
        let buffer = harness.frame(page())
        let sheet = buffer.overlays.first?.content
        let rows = harness.context.environment.overlayContentHeight
        #expect(rows < 30, "the content is taller than the area a sheet may take")
        #expect((sheet?.height ?? .max) <= rows, "the sheet stays within that area and scrolls instead")
    }
}
