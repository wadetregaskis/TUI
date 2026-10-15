//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputModifierCompositionTests.swift
//
//  A text input's own `.disabled(_:)` and `.onSubmit(_:)` compose when applied
//  twice, as SwiftUI's do: "The higher views in a view hierarchy can override
//  the value you set on this view" — a `true` anywhere wins — and every
//  `.onSubmit` a submission reaches runs (deviations sweep, likely bug 19;
//  semantic audit 61). They used to assign, so the second call discarded the
//  first.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@MainActor
@Suite("A text input's own modifiers compose")
struct TextInputModifierCompositionTests {
    private final class Log {
        var entries: [String] = []
    }

    @Test("Disabled once, a field stays disabled; enabled twice, it stays enabled")
    func disabledComposes() {
        #expect(TextField("x", text: .constant("")).disabled(true).disabled(false).isDisabled)
        #expect(TextField("x", text: .constant("")).disabled(false).disabled(true).isDisabled)
        #expect(!TextField("x", text: .constant("")).disabled(false).disabled(false).isDisabled)
        #expect(SecureField("x", text: .constant("")).disabled(true).disabled(false).isDisabled)
        #expect(TextEditor(text: .constant("")).disabled(true).disabled(false).isDisabled)
    }

    @Test("Two submit actions both run, the first applied first")
    func submitActionsChain() {
        let log = Log()
        let field = TextField("x", text: .constant(""))
            .onSubmit { log.entries.append("validate") }
            .onSubmit { log.entries.append("search") }
        field.onSubmitAction?()
        #expect(log.entries == ["validate", "search"])
        let secure = SecureField("x", text: .constant(""))
            .onSubmit { log.entries.append("check") }
            .onSubmit { log.entries.append("sign in") }
        secure.onSubmitAction?()
        #expect(log.entries == ["validate", "search", "check", "sign in"])
    }
}
