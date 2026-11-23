//  🖥️ TUI — A Terminal UI framework for Swift
//  EditModeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("EditMode / EditButton", .rendersEnglishUI)
struct EditModeTests {
    private final class ModeBox { var mode: EditMode = .inactive }
    private func binding(_ box: ModeBox) -> Binding<EditMode> {
        Binding(get: { box.mode }, set: { box.mode = $0 })
    }

    private func renderFrame(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 3, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        manager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
    }

    @Test("EditMode.isEditing truth table")
    func isEditingTruthTable() {
        #expect(EditMode.inactive.isEditing == false)
        #expect(EditMode.transient.isEditing == true)
        #expect(EditMode.active.isEditing == true)
    }

    @Test("EditButton's label reflects the bound mode")
    func labelReflectsMode() {
        let box = ModeBox()
        func text() -> String {
            let context = makeBareRenderContext(width: 20, height: 3)
            return renderToBuffer(EditButton().environment(\.editMode, binding(box)), context: context)
                .lines.joined()
        }
        #expect(text().contains("Edit"), "inactive → Edit")
        box.mode = .active
        #expect(text().contains("Done"), "active → Done")
    }

    @Test("EditButton's Edit and Done are TUI's words, in the subtree's language")
    func labelIsLocalised() {
        let box = ModeBox()
        func text() -> String {
            let context = makeBareRenderContext(width: 20, height: 3)
            let button = EditButton().environment(\.editMode, binding(box))
                .environment(\.locale, Locale(identifier: "de"))
            return renderToBuffer(button, context: context).lines.joined()
        }
        // `button.edit` and `button.done` in de.json; they were the English
        // literals "Edit" and "Done", which no table has.
        #expect(text().contains("Bearbeiten"), "inactive → Bearbeiten: \(text())")
        box.mode = .active
        #expect(text().contains("Fertig"), "active → Fertig: \(text())")
    }

    @Test("EditButton cannot take focus without an editMode in scope (it is disabled)")
    func disabledWithoutEditMode() {
        let manager = FocusManager()
        renderFrame(EditButton(), TUIContext(), manager)
        // A lone *enabled* button auto-focuses; a disabled one (canBeFocused ==
        // false) does not — so nothing being focused proves it is disabled.
        let focusedAny = manager.registeredFocusIDsInActiveSection().contains { manager.isFocused(id: $0) }
        #expect(!focusedAny, "with no \\.editMode binding the button is disabled and can't be focused")
    }

    @Test("Activating EditButton toggles the bound mode")
    func activationToggles() {
        let box = ModeBox()
        let manager = FocusManager()
        renderFrame(EditButton().environment(\.editMode, binding(box)), TUIContext(), manager)
        // The lone button auto-focuses; Enter fires its action.
        _ = manager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(box.mode == .active, "activating from .inactive turns editing on")
    }
}
