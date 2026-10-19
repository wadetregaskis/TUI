//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoManagerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

/// `TextField` and `TextEditor` register their edits with the app's undo
/// manager (decisions A1), so undo means something by default: Ctrl-minus and
/// the status bar undo typing, a control's Ctrl-Z undoes the app's newest
/// step, and redo puts it back.
@MainActor
@Suite("Text controls and the app's undo manager")
struct TextUndoManagerTests {

    private final class TextBox {
        var value = ""
    }

    /// Steps are explicit groups here, so a test does not depend on a run
    /// loop turning: each registration is its own step, as each event's are
    /// in a running app.
    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    private func typed(_ text: String) -> [KeyEvent] {
        text.map { KeyEvent(character: $0) }
    }

    /// `text` typed a character at a time at the start of the text, Home
    /// before each: every character a step of its own, since a caret moved
    /// elsewhere ends a run of typing (decisions-D1K B-D1K-6). The text ends
    /// up reversed.
    private func typedApart(_ text: String) -> [KeyEvent] {
        text.flatMap { [KeyEvent(key: .home), KeyEvent(character: $0)] }
    }

    private static let undoKey = KeyEvent.parse([0x1F])!
    private static let redoKey = KeyEvent(key: .character("Z"), ctrl: true, shift: true)
    private static let controlZ = KeyEvent(key: .character("z"), ctrl: true)

    private func field(_ box: TextBox) -> some View {
        TextField("Name", text: Binding(get: { box.value }, set: { box.value = $0 }))
    }

    @Test("A field's typing is the app's to undo, and its undo the app's to redo")
    func fieldTypingUndoesAndRedoes() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typedApart("ab") + [Self.undoKey]) { field(box) }
        #expect(box.value == "a")
        #expect(manager.canUndo && manager.canRedo)
        harness.play([Self.undoKey, Self.redoKey, Self.redoKey]) { field(box) }
        #expect(box.value == "ba")
        #expect(!manager.canRedo)
    }

    @Test("A field's Ctrl-Z undoes the app's newest step, as ⌘Z undoes a window's")
    func fieldControlZIsTheAppsUndo() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("x")) { field(box) }
        // The app registers something after the typing.
        final class Flag { var on = true }
        let flag = Flag()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: flag) { $0.on = false }
        manager.endUndoGrouping()
        harness.play([Self.controlZ]) { field(box) }
        #expect(!flag.on, "the app's step was newest")
        #expect(box.value == "x")
        harness.play([Self.controlZ]) { field(box) }
        #expect(box.value.isEmpty)
    }

    @Test("A field's undo stays in the app's history when it loses the focus, as its own history always did")
    func fieldKeepsUndoOnFocusLoss() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                self.field(box)
                Button("Other") {}
            }
        }
        harness.play(typedApart("ab") + [KeyEvent(key: .tab), Self.undoKey], page)
        #expect(box.value == "a")
        harness.play([KeyEvent(key: .tab, shift: true), Self.controlZ], page)
        #expect(box.value.isEmpty, "and the field's own Ctrl-Z after it")
    }

    private final class Flag {
        var on = true
    }

    @Test("A control that leaves the screen takes its steps out of the app's history", arguments: [false, true])
    func removedControlForgetsItsSteps(editor: Bool) {
        let manager = makeManager()
        let box = TextBox()
        let shown = Flag()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                if shown.on {
                    if editor {
                        TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
                    } else {
                        self.field(box)
                    }
                }
                Button("Other") {}
            }
        }
        harness.play(typedApart("abc") + [Self.undoKey], page)
        #expect(box.value == "ba")
        #expect(manager.canUndo && manager.canRedo)
        shown.on = false
        harness.frame(page())
        harness.frame(page())
        #expect(!manager.canUndo && !manager.canRedo, "no step left whose control is gone")
        harness.play([Self.undoKey, Self.redoKey], page)
        #expect(box.value == "ba")
    }

    /// Holds the only reference to a field's handler, for another thread to
    /// let go of.
    private final class HandlerHolder: @unchecked Sendable {
        var handler: TextFieldHandler?
    }

    /// A field's handler, typed into, with the app's manager and the
    /// harness's departed steps, as a field's render gives it them — held by
    /// nothing but the holder.
    private func typedHandler(
        _ text: String, box: TextBox, manager: UndoManager, harness: InputChainHarness
    ) -> HandlerHolder {
        let handler = TextFieldHandler(focusID: "field", text: Binding(get: { box.value }, set: { box.value = $0 }))
        handler.undoManager = manager
        handler.departedUndoSteps = harness.tui.departedUndoSteps
        for key in typed(text) { _ = handler.handleKeyEvent(key) }
        let holder = HandlerHolder()
        holder.handler = handler
        return holder
    }

    @Test("A control freed on another thread leaves the manager alone, and the next frame takes its steps out")
    func freedOffTheMainActor() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let holder = typedHandler("ab", box: box, manager: manager, harness: harness)
        #expect(box.value == "ab" && manager.canUndo)
        // A deinitialiser promises no isolation: this one runs on a thread that
        // is not the main actor's, as one could on Linux, where the main actor
        // is not the main thread.
        let freed = DispatchSemaphore(value: 0)
        Thread {
            holder.handler = nil
            freed.signal()
        }.start()
        freed.wait()
        #expect(manager.canUndo, "the manager is the main actor's; the control did not touch it")
        harness.frame(Text("page"))
        // Deferred to a task instead, as 872696f4c did off the main thread,
        // the steps were still here: the frame ran first.
        #expect(!manager.canUndo, "taken out as the frame began, before its status bar")
    }

    @Test("A step the control's own history let go of past its limit leaves the app's history with it")
    func droppedPastTheLimit() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typedApart(String(repeating: "x", count: 53))) { field(box) }
        harness.play(Array(repeating: Self.undoKey, count: 50)) { field(box) }
        #expect(box.value == "xxx", "the fifty newest steps undone")
        #expect(!manager.canUndo, "the three oldest, whose states the field let go of, are not offered")
        #expect(manager.canRedo)
    }

    @Test("An editor's edits are the app's to undo, across a change of focus")
    func editorEdits() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
                Button("Other") {}
            }
        }
        harness.play(typedApart("hi") + [KeyEvent(key: .tab), Self.undoKey], page)
        #expect(box.value == "h")
        harness.play([Self.redoKey], page)
        #expect(box.value == "ih")
    }

    @Test("Text the app replaced is not brought back, and its steps are forgotten")
    func replacementForgetsSteps() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("ab")) { field(box) }
        box.value = "other"
        harness.play([KeyEvent(key: .end)] + typed("!")) { field(box) }
        #expect(box.value == "other!")
        harness.play([Self.undoKey, Self.undoKey]) { field(box) }
        #expect(box.value == "other")
        #expect(!manager.canUndo)
    }

    /// Registers an app step of its own on `manager`, which clears `flag`
    /// when undone.
    private func registerAppStep(_ flag: Flag, on manager: UndoManager) {
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: flag) { $0.on = false }
        manager.endUndoGrouping()
    }

    @Test("Text the app replaced takes the control's steps out at the next frame, before any key", arguments: [false, true])
    func replacementSeenAtRender(editor: Bool) {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            VStack {
                if editor {
                    TextEditor(text: Binding(get: { box.value }, set: { box.value = $0 }))
                } else {
                    self.field(box)
                }
            }
        }
        harness.play(typed("hello"), page)
        #expect(box.value == "hello")
        box.value = ""
        harness.frame(page())
        // No key yet: what the status bar, built after the page, would offer.
        #expect(!manager.canUndo, "five undos that would each do nothing")
    }

    @Test("A field cleared on submit offers no undo for the cleared typing")
    func clearedOnSubmit() {
        let manager = makeManager()
        let box = TextBox()
        let older = Flag()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            TextField("Msg", text: Binding(get: { box.value }, set: { box.value = $0 })).onSubmit { box.value = "" }
        }
        registerAppStep(older, on: manager)
        harness.play(typed("hello") + [KeyEvent(key: .enter)], page)
        #expect(box.value.isEmpty)
        harness.play([Self.undoKey], page)
        #expect(!older.on)
        #expect(!manager.canUndo)
    }

    @Test("An undo in the same burst of input as the replacement is the only one spent on it")
    func replacementAndUndoInOneBurst() {
        let manager = makeManager()
        let box = TextBox()
        let older = Flag()
        let harness = InputChainHarness(undoManager: manager)
        let page = {
            TextField("Msg", text: Binding(get: { box.value }, set: { box.value = $0 })).onSubmit { box.value = "" }
        }
        registerAppStep(older, on: manager)
        harness.play(typed("hello"), page)
        // Return and Ctrl-minus read together: no frame between them.
        harness.press(KeyEvent(key: .enter))
        harness.press(Self.undoKey)
        #expect(older.on, "the field's newest step was undone, and found the text replaced")
        harness.frame(page())
        harness.play([Self.undoKey], page)
        #expect(!older.on, "the field's other four left at the frame")
        #expect(!manager.canUndo)
    }

    @Test("The run loop takes a freed control's steps out before it builds the status bar")
    func departedStepsLeaveBeforeTheBar() {
        let manager = makeManager()
        let harness = RenderLoopHarness()
        harness.tuiContext.undoManager = manager
        harness.statusBar.undoManager = manager
        // A step registered against a mark, as a text control registers its
        // edits.
        let mark = TextUndoMark()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: mark) { _ in }
        manager.endUndoGrouping()
        let loop = harness.loop(PageApp())
        loop.render()
        // A bordered bottom bar of one row of hints: the frame's last three rows.
        let drawnBar = { loop.diffWriter.shownLines.suffix(3).joined() }
        #expect(drawnBar().contains("undo"))
        // The control holding it goes away.
        harness.tuiContext.departedUndoSteps.add([mark], from: manager)
        loop.render()
        #expect(!manager.canUndo)
        #expect(!drawnBar().contains("undo"), "the bar this frame built does not offer it")
    }

    @Test("Without an app, a field's Ctrl-Z and Ctrl-Shift-Z work on its own history")
    func fieldWithoutAnApp() {
        let box = TextBox()
        let harness = InputChainHarness()
        harness.play(typedApart("ab") + [Self.controlZ, Self.controlZ, Self.redoKey]) { field(box) }
        #expect(box.value == "a")
    }

    @Test("A secure field's typing stays out of the app's history")
    func secureFieldStaysOut() {
        let manager = makeManager()
        let box = TextBox()
        let harness = InputChainHarness(undoManager: manager)
        harness.play(typed("pw")) {
            SecureField("Password", text: Binding(get: { box.value }, set: { box.value = $0 }))
        }
        #expect(box.value == "pw")
        #expect(!manager.canUndo)
    }
}

/// One page and nothing else, for a frame of the whole run loop.
private struct PageApp: App {
    var body: some Scene {
        WindowGroup {
            Text("page").toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}
