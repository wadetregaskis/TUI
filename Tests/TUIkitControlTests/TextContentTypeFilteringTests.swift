//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextContentTypeFilteringTests.swift
//
//  No test ever applied `.textContentType(_:)`, so `handler.textContentType`
//  was nil in every test in the suite — which made BOTH filters dead code:
//  `guard textContentType?.isAllowed(char) ?? true` always took the `?? true`
//  arm, and the `if let contentType` body in `insertText` never ran. The
//  filter is the whole feature (a terminal has no autofill), so what was
//  untested was not an edge case but the point.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@Suite("Text content type filtering, from the view down")
struct TextContentTypeFilteringTests {

    private final class TextBox: @unchecked Sendable {
        var text: String
        init(_ text: String) { self.text = text }
    }

    /// A handler on its own binding and clipboard, so these run in parallel
    /// with everything else — the shape `SecureFieldClipboardTests` uses.
    private func makeHandler(
        _ contentType: TextContentType?, clipboard: FakeClipboard = FakeClipboard()
    ) -> (TextFieldHandler, TextBox) {
        let box = TextBox("")
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let handler = TextFieldHandler(focusID: "field", text: binding, cursorPosition: 0)
        handler.textContentType = contentType
        handler.clipboard = clipboard.access
        return (handler, box)
    }

    @Test("A typed character the content type rejects never reaches the binding")
    func typingIsFiltered() {
        let (handler, box) = makeHandler(.integer)
        for character in "a-1b2" { handler.insertCharacter(character) }
        #expect(box.text == "-12")

        // The control: without a content type the same keys all land, so the
        // assertion above is about the filter and not about the insert path.
        let (unfiltered, plain) = makeHandler(nil)
        for character in "a-1b2" { unfiltered.insertCharacter(character) }
        #expect(plain.text == "a-1b2")
    }

    @Test("A pasted string is filtered, and one filtered to nothing inserts nothing")
    func pasteIsFiltered() {
        let board = FakeClipboard()
        board.contents = "a1b2"
        let (handler, box) = makeHandler(.integer, clipboard: board)
        #expect(handler.handleKeyEvent(KeyEvent(key: .character("v"), ctrl: true)))
        #expect(box.text == "12")

        // Nothing usable in the paste: the field must be left exactly as it
        // was, not cleared and not given the raw text.
        board.contents = "hello"
        #expect(handler.handleKeyEvent(KeyEvent(key: .character("v"), ctrl: true)))
        #expect(box.text == "12")
    }

    @Test("A password field is not filtered at either door")
    func passwordPassesEverything() {
        let board = FakeClipboard()
        board.contents = "p@$$ w0rd!"
        let (handler, box) = makeHandler(.password, clipboard: board)
        for character in "!@ " { handler.insertCharacter(character) }
        #expect(box.text == "!@ ")
        #expect(handler.handleKeyEvent(KeyEvent(key: .character("v"), ctrl: true)))
        #expect(box.text == "!@ p@$$ w0rd!")
    }

    /// The tests above set `textContentType` on the handler themselves, so
    /// they say nothing about whether the modifier reaches it. This one
    /// renders the real views and drives real keys, so deleting
    /// `handler.textContentType = context.environment.textContentType` from
    /// either field's sync block fails here.
    @MainActor
    @Test("The modifier reaches both fields' handlers")
    func wiringFromTheViewDown() {
        func type(_ characters: String, secure: Bool, contentType: TextContentType?) -> String {
            let box = StateBox("")
            let binding = Binding(get: { box.value }, set: { box.value = $0 })
            let focusManager = FocusManager()
            let context = makeRenderContext { environment, _ in
                environment.focusManager = focusManager
            }
            let field =
                secure
                ? AnyView(SecureField("secret", text: binding))
                : AnyView(TextField("label", text: binding))
            let view = contentType.map { AnyView(field.textContentType($0)) } ?? field

            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()

            for character in characters {
                _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character(character)))
            }
            return box.value
        }

        #expect(type("a7b", secure: false, contentType: .integer) == "7")
        #expect(type("a7b", secure: true, contentType: .integer) == "7")
        // And with no content type the same keys all land, so the two above
        // are about the modifier rather than about the keys not arriving.
        #expect(type("a7b", secure: false, contentType: nil) == "a7b")
        #expect(type("a7b", secure: true, contentType: nil) == "a7b")
    }

    // MARK: - Never in silence (deviation T8, the owner's ruling of 2026-10-13)

    @Test("A typed character the content type turns away rings the bell; one it takes does not")
    func typingRingsForWhatItRefuses() {
        let (handler, box) = makeHandler(.integer)
        let bell = TerminalBell(requestFrame: {})
        handler.bell = bell
        handler.insertCharacter("7")
        #expect(bell.ringCount == 0)
        handler.insertCharacter("a")
        #expect(bell.ringCount == 1)
        #expect(box.text == "7")
    }

    @Test("A paste rings the bell once for whatever it drops, and a clean paste not at all")
    func pasteRingsOnce() {
        let (handler, box) = makeHandler(.integer)
        let bell = TerminalBell(requestFrame: {})
        handler.bell = bell
        handler.insertText("12")
        #expect(bell.ringCount == 0)
        handler.insertText("3a4b5c")
        #expect(bell.ringCount == 1)
        #expect(box.text == "12345")
    }

    @Test("A bell rung many times between frames is one BEL at the next")
    func oneBellAFrame() {
        let frames = TextBox("")
        let bell = TerminalBell(requestFrame: { frames.text += "f" })
        bell.ring()
        bell.ring()
        bell.ring()
        #expect(frames.text == "fff", "a ring did not ask for the frame that sounds it")
        #expect(bell.takePending() == "\u{07}")
        #expect(bell.takePending().isEmpty)
    }

    /// The field takes its environment's bell when it is made, so a typed
    /// refusal from a real `TextField` or `SecureField` rings the app's.
    @MainActor
    @Test("A field's refusal rings its environment's bell")
    func fieldsRingTheirEnvironmentsBell() {
        func rings(secure: Bool) -> Int {
            let box = StateBox("")
            let binding = Binding(get: { box.value }, set: { box.value = $0 })
            let focusManager = FocusManager()
            let bell = TerminalBell(requestFrame: {})
            let context = makeRenderContext { environment, _ in
                environment.focusManager = focusManager
                environment.terminalBell = bell
            }
            let field =
                secure
                ? AnyView(SecureField("secret", text: binding)) : AnyView(TextField("label", text: binding))
            focusManager.beginRenderPass()
            _ = renderToBuffer(field.textContentType(.oneTimeCode), context: context)
            focusManager.endRenderPass()
            for character in "1x2" { _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character(character))) }
            #expect(box.value == "12")
            return bell.ringCount
        }
        #expect(rings(secure: false) == 1)
        #expect(rings(secure: true) == 1)
    }

    // MARK: - Every valid character

    @Test(
        "Each type admits every character a valid value holds",
        arguments: [
            (TextContentType.emailAddress, "o'brien+tag!#$%&*/=?^_`{|}~.x@mail-host.example"),
            (.emailAddress, "jörg@bücher.example"),
            (.integer, "+42"),
            (.integer, "-42"),
            (.decimal, "+3,25"),
            (.decimal, "-3.25"),
            (.telephoneNumber, "+49 (030) 123-45.67/89 #*"),
        ])
    func admitsValidValues(contentType: TextContentType, value: String) {
        #expect(contentType.filterString(value) == value)
    }

    @Test(
        "Each type still turns away what no valid value holds",
        arguments: [
            (TextContentType.emailAddress, "a b,c;d<e>f@g", "abcdef@g"),
            (.integer, "4.2", "42"),
            (.decimal, "1e5", "15"),
            (.telephoneNumber, "030-CALL-NOW", "030--"),
        ])
    func refusesInvalidCharacters(contentType: TextContentType, value: String, kept: String) {
        #expect(contentType.filterString(value) == kept)
    }
}
