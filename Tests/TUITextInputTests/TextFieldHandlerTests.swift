//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldHandlerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

// MARK: - TextFieldHandler Tests

@MainActor
@Suite("TextFieldHandler Tests")
struct TextFieldHandlerTests {

    // MARK: - Initialization

    @Test("Handler initializes with correct defaults")
    func initializationDefaults() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding)

        #expect(handler.focusID == "test")
        #expect(handler.canBeFocused == true)
        #expect(handler.cursorPosition == 5)  // End of "Hello"
    }

    @Test("Handler initializes with custom cursor position")
    func initializationWithCursorPosition() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        #expect(handler.cursorPosition == 2)
    }

    @Test("Handler initializes with empty text")
    func initializationEmptyText() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })

        let handler = TextFieldHandler(focusID: "test", text: binding)

        #expect(handler.cursorPosition == 0)
    }

    // MARK: - Character Insertion

    @Test(
        "insertCharacter splices at the cursor and advances it",
        arguments: [
            // (initialText, cursor, char, expectedText, expectedCursor)
            ("Hello", 5, "!", "Hello!", 6),  // at end
            ("Hllo", 1, "e", "Hello", 2),  // in the middle
            ("ello", 0, "H", "Hello", 1),  // at the start
            ("HelloWorld", 5, " ", "Hello World", 6),  // space
        ])
    func insertCharacter(
        initialText: String, cursor: Int, char: Character, expectedText: String, expectedCursor: Int
    ) {
        var text = initialText
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: cursor)

        handler.insertCharacter(char)

        #expect(text == expectedText)
        #expect(handler.cursorPosition == expectedCursor)
    }

    // MARK: - Delete Backward (Backspace)

    @Test(
        "deleteBackward removes the character before the cursor (no-op at the start)",
        arguments: [
            // (cursor, expectedText, expectedCursor) on "Hello"
            (5, "Hell", 4),  // at end
            (3, "Helo", 2),  // in the middle
            (0, "Hello", 0),  // at the start: nothing to delete
        ])
    func deleteBackward(cursor: Int, expectedText: String, expectedCursor: Int) {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: cursor)

        handler.deleteBackward()

        #expect(text == expectedText)
        #expect(handler.cursorPosition == expectedCursor)
    }

    // MARK: - Delete Forward (Delete Key)

    @Test(
        "deleteForward removes the character at the cursor (no-op at the end)",
        arguments: [
            // (cursor, expectedText, expectedCursor) on "Hello"
            (0, "ello", 0),  // at the start
            (2, "Helo", 2),  // in the middle
            (5, "Hello", 5),  // at the end: nothing to delete
        ])
    func deleteForward(cursor: Int, expectedText: String, expectedCursor: Int) {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: cursor)

        handler.deleteForward()

        #expect(text == expectedText)
        #expect(handler.cursorPosition == expectedCursor)
    }

    // MARK: - Cursor Movement

    @Test("Move cursor left")
    func moveCursorLeft() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        handler.moveCursorLeft()

        #expect(handler.cursorPosition == 4)
    }

    @Test("Move cursor left at start stays at 0")
    func moveCursorLeftAtStart() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        handler.moveCursorLeft()

        #expect(handler.cursorPosition == 0)
    }

    @Test("Move cursor right")
    func moveCursorRight() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 2)

        handler.moveCursorRight()

        #expect(handler.cursorPosition == 3)
    }

    @Test("Move cursor right at end stays at end")
    func moveCursorRightAtEnd() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)  // Cursor at end

        handler.moveCursorRight()

        #expect(handler.cursorPosition == 5)
    }

    // MARK: - Key Event Handling

    @Test("Character key event inserts character")
    func handleCharacterKeyEvent() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .character("A")))

        #expect(handled == true)
        #expect(text == "A")
    }

    @Test("Backspace key event deletes backward")
    func handleBackspaceKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .backspace))

        #expect(handled == true)
        #expect(text == "A")
    }

    @Test("Delete key event deletes forward")
    func handleDeleteKeyEvent() {
        var text = "AB"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let handled = handler.handleKeyEvent(KeyEvent(key: .delete))

        #expect(handled == true)
        #expect(text == "B")
    }

    @Test(
        "A movement key event routes to the cursor",
        arguments: [
            // (key, text, startCursor, expectedCursor)
            (Key.left, "AB", 2, 1),
            (.right, "AB", 0, 1),
            (.home, "Hello", 5, 0),
            (.end, "Hello", 0, 5),
        ])
    func movementKeyEvent(key: Key, text initialText: String, startCursor: Int, expectedCursor: Int) {
        var text = initialText
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: startCursor)

        let handled = handler.handleKeyEvent(KeyEvent(key: key))

        #expect(handled == true)
        #expect(handler.cursorPosition == expectedCursor)
    }

    @Test("Enter key event triggers onSubmit")
    func handleEnterKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        var submitCalled = false
        handler.onSubmit = { submitCalled = true }

        let handled = handler.handleKeyEvent(KeyEvent(key: .enter))

        #expect(handled == true)
        #expect(submitCalled == true)
    }

    @Test("Unhandled key event returns false")
    func handleUnhandledKeyEvent() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        let handled = handler.handleKeyEvent(KeyEvent(key: .f1))

        #expect(handled == false)
    }

    // MARK: - Cursor Clamping

    @Test("Clamp cursor position when text shrinks")
    func clampCursorPosition() {
        var text = "Hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding)

        // Simulate external text change
        text = "Hi"
        handler.text = binding
        handler.clampCursorPosition()

        #expect(handler.cursorPosition == 2)  // Clamped to "Hi".count
    }

    // MARK: - Ctrl-U: kill to the start (LineDiscardTests has the rest)

    @Test("Ctrl-U kills the text before the caret, and leaves the rest and the caret at the start")
    func ctrlUKillsToStart() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("u"), ctrl: true))
        #expect(consumed)
        #expect(text == "brown fox")
        #expect(handler.cursorPosition == 0)
    }

    // MARK: - Option / Alt + arrow: word navigation

    @Test("Option-Left moves to the start of the previous word")
    func optionLeftMovesToPreviousWord() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 16, "Cursor moved to start of 'fox'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 10, "Cursor moved to start of 'brown'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 4, "Cursor moved to start of 'quick'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 0, "Cursor moved to start of 'the'")
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true))
        #expect(handler.cursorPosition == 0, "At start: Option-Left is a no-op")
    }

    @Test("Option-Right moves to the end of the next word")
    func optionRightMovesToNextWord() {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 3, "End of 'the'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 9, "End of 'quick'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 15, "End of 'brown'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 19, "End of 'fox'")
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true))
        #expect(handler.cursorPosition == 19, "At end: Option-Right is a no-op")
    }

    @Test("Option-b is a synonym for Option-Left (readline word-back)")
    func optionBSynonymForOptionLeft() {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("b"), alt: true))
        #expect(consumed)
        #expect(handler.cursorPosition == 6, "Cursor at start of 'world'")
        #expect(text == "hello world", "No 'b' was inserted")
    }

    @Test("Option-f is a synonym for Option-Right (readline word-forward)")
    func optionFSynonymForOptionRight() {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        let consumed = handler.handleKeyEvent(
            KeyEvent(key: .character("f"), alt: true))
        #expect(consumed)
        #expect(handler.cursorPosition == 5, "Cursor at end of 'hello'")
        #expect(text == "hello world", "No 'f' was inserted")
    }

    @Test("Shift+Option+Left extends selection to the previous word boundary")
    func shiftOptionLeftExtendsSelectionToPreviousWord() throws {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        #expect(handler.cursorPosition == 16, "Cursor at start of 'fox'")
        #expect(handler.selectionAnchor == 19, "Anchor at original end")
        let range1 = try #require(handler.selectionRange)
        #expect(range1 == 16..<19, "Selection spans 'fox'")

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        #expect(handler.cursorPosition == 10, "Cursor at start of 'brown'")
        let range2 = try #require(handler.selectionRange)
        #expect(range2 == 10..<19, "Selection now spans 'brown fox'")
    }

    @Test("Shift+Option+Right extends selection to the next word boundary")
    func shiftOptionRightExtendsSelectionToNextWord() throws {
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 3, "Cursor at end of 'the'")
        let range1 = try #require(handler.selectionRange)
        #expect(range1 == 0..<3, "Selection spans 'the'")

        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 9, "Cursor at end of 'quick'")
        let range2 = try #require(handler.selectionRange)
        #expect(range2 == 0..<9, "Selection now spans 'the quick'")
    }

    @Test("Shift+Option+Right shrinks an existing leftward selection")
    func shiftOptionRightShrinksLeftwardSelection() throws {
        // Start with cursor in the middle, extend leftward, then shrink
        // back by stepping right one word at a time.
        var text = "the quick brown fox"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 15)

        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        _ = handler.handleKeyEvent(KeyEvent(key: .left, alt: true, shift: true))
        // Anchor stays at 15, cursor now at 4 (start of 'quick').
        #expect(handler.cursorPosition == 4)
        #expect(handler.selectionAnchor == 15)

        // Stepping right with Shift+Option moves the cursor end without
        // touching the anchor, so the selection contracts.
        _ = handler.handleKeyEvent(KeyEvent(key: .right, alt: true, shift: true))
        #expect(handler.cursorPosition == 9, "Cursor at end of 'quick'")
        #expect(handler.selectionAnchor == 15, "Anchor unchanged")
        let range = try #require(handler.selectionRange)
        #expect(range == 9..<15)
    }

    @Test("Shift+Option+b/f mirror Shift+Option+Left/Right")
    func shiftOptionLetterSynonyms() throws {
        var text = "hello world"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(
            focusID: "test", text: binding, cursorPosition: text.count)

        _ = handler.handleKeyEvent(KeyEvent(key: .character("b"), alt: true, shift: true))
        #expect(handler.cursorPosition == 6)
        let range = try #require(handler.selectionRange)
        #expect(range == 6..<11, "Selection spans 'world'")
        #expect(text == "hello world", "No 'b' was inserted")
    }

    // MARK: - Click column → character index

    /// One display cell per character — the plain-ASCII case.
    private func narrowWidths(_ count: Int) -> [Int] {
        Array(repeating: 1, count: count)
    }

    @Test("A click column maps to a character index (unscrolled field)")
    func clickColumnMapsToIndex() {
        var text = "hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        // With the whole word visible, the click column is the character index.
        #expect(handler.characterIndex(forColumn: 0, contentWidth: 20, displayWidths: narrowWidths(5)) == 0)
        #expect(handler.characterIndex(forColumn: 3, contentWidth: 20, displayWidths: narrowWidths(5)) == 3)
        // Past the end clamps to the text length; negatives clamp to the start.
        #expect(handler.characterIndex(forColumn: 40, contentWidth: 20, displayWidths: narrowWidths(5)) == 5)
        #expect(handler.characterIndex(forColumn: -2, contentWidth: 20, displayWidths: narrowWidths(5)) == 0)
    }

    @Test("A click column maps through the horizontal scroll offset")
    func clickColumnMapsThroughScroll() {
        var text = "abcdefghij"  // 10 chars
        let binding = Binding(get: { text }, set: { text = $0 })
        // Cursor at the end scrolls the field: contentWidth 5 → visibleTextWidth 4,
        // so scrollOffset = 10 - 4 = 6; visible window starts at index 6.
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 10)
        #expect(handler.characterIndex(forColumn: 0, contentWidth: 5, displayWidths: narrowWidths(10)) == 6)
        #expect(handler.characterIndex(forColumn: 2, contentWidth: 5, displayWidths: narrowWidths(10)) == 8)
    }

    @Test("A click on either cell of a wide character lands on that character")
    func clickColumnMapsWideCharacters() {
        var text = "😀😀ab"  // cells: [0,1]=😀 [2,3]=😀 [4]=a [5]=b
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)
        let widths = [2, 2, 1, 1]

        #expect(handler.characterIndex(forColumn: 0, contentWidth: 20, displayWidths: widths) == 0)
        #expect(handler.characterIndex(forColumn: 1, contentWidth: 20, displayWidths: widths) == 0)
        #expect(handler.characterIndex(forColumn: 2, contentWidth: 20, displayWidths: widths) == 1)
        #expect(handler.characterIndex(forColumn: 3, contentWidth: 20, displayWidths: widths) == 1)
        #expect(handler.characterIndex(forColumn: 4, contentWidth: 20, displayWidths: widths) == 2)
        #expect(handler.characterIndex(forColumn: 5, contentWidth: 20, displayWidths: widths) == 3)
        #expect(handler.characterIndex(forColumn: 6, contentWidth: 20, displayWidths: widths) == 4)
    }

    @Test("The click inverse mirrors the renderer's CELL-based scroll")
    func clickColumnMapsThroughCellScroll() {
        var text = "😀😀😀😀"  // 8 cells, 4 chars
        let binding = Binding(get: { text }, set: { text = $0 })
        // Caret at the end: cursorCellX = 8; contentWidth 5 → scroll starts at
        // cell 8 - 4 = 4, i.e. the window opens on the third emoji.
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 4)
        let widths = [2, 2, 2, 2]
        #expect(handler.characterIndex(forColumn: 0, contentWidth: 5, displayWidths: widths) == 2)
        #expect(handler.characterIndex(forColumn: 2, contentWidth: 5, displayWidths: widths) == 3)
        #expect(handler.characterIndex(forColumn: 4, contentWidth: 5, displayWidths: widths) == 4)
    }

    @Test("A click past the content window's right edge clamps into the window")
    func clickPastRightEdgeClampsIntoWindow() {
        // 20 characters in a 10-cell content area, caret at 5 so the window is
        // cells 0..<10. The closing cap sits one column past that, and a combo
        // box's disclosure two further out — both used to map to an OFF-SCREEN
        // character, whose caret-anchored scroll then shifted the field.
        var text = "abcdefghijklmnopqrst"
        let handler = TextFieldHandler(
            focusID: "test",
            text: Binding(get: { text }, set: { text = $0 }),
            cursorPosition: 5)
        let widths = narrowWidths(20)

        let atCap = handler.characterIndex(forColumn: 10, contentWidth: 10, displayWidths: widths)
        #expect(atCap == 9, "the closing cap puts the caret on the last VISIBLE character")

        let atDisclosure = handler.characterIndex(
            forColumn: 12, contentWidth: 10, displayWidths: widths)
        #expect(atDisclosure == 9, "so does a combo box's disclosure, two cells further out")

        // The symptom: a caret inside the window cannot scroll it.
        for index in [atCap, atDisclosure] {
            let cellX = widths[0..<index].reduce(0, +)
            #expect(
                TextFieldContentRenderer.scrollCells(cursorCellX: cellX, width: 10) == 0,
                "a cap click must not walk the field sideways")
        }
    }

    @Test("The right-edge clamp is in cells, not characters")
    func rightEdgeClampIsCellBased() {
        // Ten emoji: 10 characters, 20 cells. A 10-cell window shows five of
        // them, so the cap must land on emoji 4 — clamping the CHARACTER index
        // to contentWidth - 1 would say 9, which is not even on screen.
        var text = String(repeating: "😀", count: 10)
        let handler = TextFieldHandler(
            focusID: "test",
            text: Binding(get: { text }, set: { text = $0 }),
            cursorPosition: 0)
        let widths = Array(repeating: 2, count: 10)

        #expect(handler.characterIndex(forColumn: 10, contentWidth: 10, displayWidths: widths) == 4)
        // A wide character straddling the right edge still resolves to itself:
        // in a 9-cell window emoji 4 occupies cells 8-9, and cell 8 is its own.
        #expect(handler.characterIndex(forColumn: 8, contentWidth: 9, displayWidths: widths) == 4)
    }

    @Test("Wide character at right edge keeps room for two cells in scrollCells")
    func scrollCellsWideCharacter() {
        // In a 10-wide content area:
        // Text: 12 'a's (12 cells) followed by '😀' (2 cells) at index 12.
        // Caret on emoji (cursorCellX = 12):
        // When caretCells is 1, scrollCells would be 12 - 9 = 3 (window 3..<13, emoji at 12..14 is cut off).
        // When caretCells is 2, scrollCells is 12 + 2 - 10 = 4 (window 4..<14, emoji at 12..14 fits!).
        let scrollSingle = TextFieldContentRenderer.scrollCells(cursorCellX: 12, caretCells: 1, width: 10)
        #expect(scrollSingle == 3)
        let scrollWide = TextFieldContentRenderer.scrollCells(cursorCellX: 12, caretCells: 2, width: 10)
        #expect(scrollWide == 4)

        // characterIndex maps through the wide-character scroll
        var text = "aaaaaaaaaaaa😀b"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 12)
        let widths = Array(repeating: 1, count: 12) + [2, 1]
        // In a 10-wide content area with scrollStart = 4:
        // Column 8 is cell 4 + 8 = 12, which is index 12 (the emoji)
        #expect(handler.characterIndex(forColumn: 8, contentWidth: 10, displayWidths: widths) == 12)
    }

    @Test("Clicking an unfocused field maps through drawnScrollCells 0")
    func unfocusedFieldClickMapsThroughDrawnScroll() {
        var text = "abcdefghijklmnopqrstuvwxyz0123" // 30 characters
        let binding = Binding(get: { text }, set: { text = $0 })
        // Previous cursor was left at the end (position 30)
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 30)
        let widths = narrowWidths(30)
        // When unfocused, drawnScrollCells is 0
        handler.drawnScrollCells = 0
        // Clicking column 3 of the 10-wide content area must land on character 3, not 24
        #expect(handler.characterIndex(forColumn: 3, contentWidth: 10, displayWidths: widths) == 3)
    }

    @Test("displayCharacter maps tabs to space and control characters to replacement character")
    func displayCharacterSanitization() {
        #expect(TextFieldHandler.displayCharacter("\t") == " ")
        #expect(TextFieldHandler.displayCharacter("\u{1B}") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("\u{00}") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("\u{07}") == "\u{FFFD}")
        #expect(TextFieldHandler.displayCharacter("a") == "a")
        #expect(TextFieldHandler.displayCharacter("\u{2028}") == "\u{2028}")
    }

    @Test("Pasted control characters are stripped in TextFieldHandler")
    func pastedControlCharactersAreStripped() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)

        // Escape injection is stripped
        handler.insertText("\u{1B}[2Jhello")
        #expect(text == "[2Jhello")

        // A tab is text, kept as TextEditor and an AppKit field keep it
        text = ""
        handler.cursorPosition = 0
        handler.insertText("col1\tcol2")
        #expect(text == "col1\tcol2")

        // Stray pure control string does nothing
        handler.insertText("\u{1B}\u{07}")
        #expect(text == "col1\tcol2")
    }

    @Test("Pasting in vertical field preserves newlines but strips escape characters")
    func verticalFieldPasting() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)
        handler.wrapWidth = 20

        handler.insertText("hello\r\n\u{1B}[31mworld\nline3")
        #expect(text == "hello\n[31mworld\nline3")
    }

    @Test("Pasting a combining mark merges with previous character and places caret correctly")
    func pastingCombiningMarkMerges() {
        var text = "e"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 1)

        // Paste combining acute accent (U+0301) after "e"
        handler.insertText("\u{0301}")
        #expect(text == "é")
        #expect(handler.cursorPosition == 1)

        // Paste combining mark followed by regular characters in the middle of text
        text = "ef"
        handler.cursorPosition = 1
        handler.insertText("\u{0301}x")
        #expect(text == "éxf")
        #expect(handler.cursorPosition == 2)
    }

    @Test("Typing a mark that merges into the character before keeps the caret after that character")
    func typingMergingMarkPlacesCaret() {
        var text = "कब"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 1)
        // A Hindi keyboard sends the vowel sign as a key of its own.
        handler.insertCharacter("\u{093F}")
        #expect(text == "किब")
        #expect(handler.cursorPosition == 1, "after कि, before ब")
    }

    @Test("A triple-click's paragraph ends at a CR LF break, which is one Character")
    func paragraphEndsAtCRLF() {
        var text = "ab\r\ncd"
        let binding = Binding(get: { text }, set: { text = $0 })
        let handler = TextFieldHandler(focusID: "test", text: binding, cursorPosition: 0)
        handler.wrapWidth = 20
        #expect(handler.range(of: .paragraph, around: 1) == 0..<3)
        #expect(handler.range(of: .paragraph, around: 3) == 3..<5)
    }
}
