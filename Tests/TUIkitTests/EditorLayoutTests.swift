//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorLayoutTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Editor layout: the document split once per text")
struct EditorLayoutTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    @Test("Lines, an empty text, and a trailing newline")
    func lines() {
        #expect(EditorLayout(text: "a\nbc").lines == [["a"], ["b", "c"]])
        #expect(EditorLayout(text: "").lines == [[]])
        #expect(EditorLayout(text: "a\n").lines == [["a"], []])
    }

    @Test("An untouched document is laid out once")
    func reusedWhileUnchanged() {
        let box = Box("one\ntwo")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0 }))
        let first = handler.layout()
        #expect(handler.layout() === first)
        box.value = "three"
        #expect(handler.layout() !== first)
        #expect(handler.readLines() == [["t", "h", "r", "e", "e"]])
    }

    /// The measure runs before the render hands the handler this frame's
    /// binding, so a measure that read the handler's binding sized the editor
    /// for the PREVIOUS document. A binding that is not a live reference — a
    /// `.constant`, `$notes[selected]` — holds what its frame was built with.
    @Test("The editor is measured for the text its binding holds now, not the text it last drew")
    func measuresTheCurrentText() {
        for wraps in [true, false] {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tui)
            func pass<T>(_ body: () -> T) -> T {
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                defer { tui.stateStorage.endRenderPass() }
                return body()
            }
            func editor(_ text: String) -> some View {
                TextEditor(text: .constant(text)).textEditorWrapsLines(wraps)
            }
            // The first frame makes the handler, holding the one-line text.
            _ = pass { renderToBuffer(editor("a"), context: context) }
            let size = pass {
                measureChild(
                    editor("1\n2\n3\n4\n5\n6"), proposal: ProposedSize(width: 30, height: nil), context: context)
            }
            #expect(size.height == 6, "wrapping: \(wraps)")
        }
    }

    /// A self-built frame loop, for the tests that measure between frames.
    struct Frames {
        let tui = TUIContext()
        let focus = FocusManager()
        let context: RenderContext

        init(width: Int, height: Int) {
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.applyRuntimeServices(from: tui)
            context = RenderContext(
                availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        }

        func pass<T>(_ body: () -> T) -> T {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            defer {
                focus.endRenderPass()
                tui.stateStorage.endRenderPass()
            }
            return body()
        }

        var handler: TextEditorHandler? { focus.currentFocused as? TextEditorHandler }
    }

    static let longDocument = Array(repeating: "aaaa bbbb cccc dddd eeee ffff gggg", count: 30)
        .joined(separator: "\n")

    struct Beside: View {
        let text: Box
        var body: some View {
            HStack(spacing: 1) {
                Text("1\n2\n3")
                TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
            }
        }
    }

    /// An HStack measures its editor at the full width, then at the width it
    /// gives it, and the editor draws at that width and a cell narrower for
    /// its scroll bar: three widths a frame, and two kept meant the whole
    /// document wrapped three times on every idle frame.
    @Test("An editor laid out at several widths a frame wraps its document once for each, not every frame")
    func idleFramesWrapNothing() throws {
        let frames = Frames(width: 30, height: 6)
        let page = Beside(text: Box(Self.longDocument))
        for _ in 0..<2 { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        let layout = try #require(frames.handler).layout()
        let made = layout.wrapsMade
        for _ in 0..<3 { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        #expect(layout.wrapsMade == made)
        #expect(layout.wrappings.count >= 3, "the widths a frame asks for are all kept")
    }

    @Test("A width no frame asks for any more is forgotten")
    func staleWidthsGo() throws {
        let layout = EditorLayout(text: Self.longDocument)
        _ = layout.wrapped(width: 10, tabWidth: .periodic(4))
        _ = layout.wrapped(width: 12, tabWidth: .periodic(4))
        layout.endFrame()
        _ = layout.wrapped(width: 12, tabWidth: .periodic(4))
        layout.endFrame()
        #expect(layout.wrappings.map(\.rows.width) == [12])
        #expect(layout.wrapsMade == 2)
    }

    @Test("An edit hands its lines over with its text")
    func editKeepsItsLines() {
        let box = Box("ab\ncd")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0 }))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("e")))
        let layout = handler.layout()
        #expect(layout.text == "ab\ncde")
        #expect(layout.lines == [["a", "b"], ["c", "d", "e"]])
        #expect(handler.layout() === layout)
    }

    @Test("A binding that keeps something else is laid out from what it keeps")
    func transformingBinding() {
        let box = Box("ab")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0.uppercased() }))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("c")))
        #expect(handler.readLines() == [["A", "B", "C"]])
    }
}
