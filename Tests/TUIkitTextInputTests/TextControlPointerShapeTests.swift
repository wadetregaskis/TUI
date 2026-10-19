//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextControlPointerShapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

/// The I-beam TUIkit's text controls give the pointer, where its controls set
/// their own shapes (decisions O12, B-O12-6).
@MainActor
@Suite("Text controls' pointer shapes")
struct TextControlPointerShapeTests {
    @Test("A text field, a secure field and a text editor give the I-beam, and only where asked")
    func iBeam() {
        let page = VStack(alignment: .leading, spacing: 0) {
            TextField("Name", text: .constant("Ada"))
            SecureField("Password", text: .constant("secret"))
            TextEditor(text: .constant("Some text")).frame(height: 3)
        }
        let harness = PointerShapeHarness(controlShapes: true)
        let buffer = harness.frame(page)
        let rows = buffer.hitTestRegions.filter { $0.focusID != nil }.map(\.offsetY)
        #expect(rows.count >= 3, "the text controls drew no regions: \(buffer.hitTestRegions)")
        for y in rows {
            #expect(harness.shape(atX: 2, y: y) == .text, "row \(y)")
        }
        let off = PointerShapeHarness()
        off.frame(page)
        #expect(off.shape(atX: 2, y: 0) == nil)
    }

    @Test("A text editor alone on a page asks for the motion its I-beam shows by")
    func editorAloneAsksForMotion() {
        let harness = PointerShapeHarness(controlShapes: true)
        harness.frame(TextEditor(text: .constant("Some text")).frame(height: 3))
        #expect(harness.dispatcher.effectiveSupport(baseConfig: .standard).motion)
        #expect(harness.shape(atX: 2, y: 0) == .text)
    }
}
