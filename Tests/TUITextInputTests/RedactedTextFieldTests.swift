//  🖥️ TUI — A Terminal UI framework for Swift
//  RedactedTextFieldTests.swift
//
//  A TextField under `.redacted(reason:)` drew what was typed, letter for
//  letter, and let it out every other way too: copied and cut, kept by Ctrl-K
//  for Ctrl-Y, its word breaks shown by Option-arrows and by a double-click.
//  Nothing in the field read the redaction at all. The owner's ruling
//  (2026-11-10): hidden text "should not reveal its contents in any way". A
//  redacted field now behaves as a SecureField does, which already did all of
//  this (`SecureFieldClipboardTests`), drawn with the redaction's glyph.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUITextInput

/// The string a field is bound to, read back after the keys.
@MainActor
private final class Bound {
    var value: String
    init(_ value: String) { self.value = value }
}

/// Every way a field's text is hidden, and the ways that leave it shown,
/// which are the control cases.
enum FieldHiding: String, CaseIterable, Sendable {
    /// `.redacted(reason: .placeholder)`.
    case placeholder
    /// `.privacySensitive()` under `.redacted(reason: .privacy)`.
    case privacy
    /// Under `.redacted(reason: .privacy)` but not marked sensitive: shown, as
    /// a `Text` there is.
    case privacyUnmarked
    /// `.unredacted()` inside `.redacted(reason: .placeholder)`: shown.
    case unredacted
    /// Not redacted at all.
    case none

    var hides: Bool { self == .placeholder || self == .privacy }

    /// The glyph each character is drawn as, where it hides.
    var glyph: Character { self == .privacy ? TerminalSymbols.maskBullet : "░" }
}

private struct FieldPage: View {
    let hiding: FieldHiding
    let vertical: Bool
    let text: Bound
    let board: FakeClipboard

    var body: some View {
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        let field = Group {
            if vertical {
                TextField("Name", text: binding, axis: .vertical).lineLimit(3)
            } else {
                TextField("Name", text: binding)
            }
        }
        Group {
            switch hiding {
            case .placeholder: field.redacted(reason: .placeholder)
            case .privacy: field.privacySensitive().redacted(reason: .privacy)
            case .privacyUnmarked: field.redacted(reason: .privacy)
            case .unredacted: field.unredacted().redacted(reason: .placeholder)
            case .none: field
            }
        }
        .environment(\.clipboardAccess, board.access)
    }
}

/// One field on an otherwise empty page, so it takes the focus on the first
/// frame and every key goes to it. Its caret starts at the end.
@MainActor
private func fieldApp(
    _ hiding: FieldHiding, _ initial: String, vertical: Bool = false
) -> (TestApp, Bound, FakeClipboard) {
    let text = Bound(initial)
    let board = FakeClipboard()
    let app = TestApp(width: 30, height: 6) {
        FieldPage(hiding: hiding, vertical: vertical, text: text, board: board)
    }
    return (app, text, board)
}

@MainActor
@Suite("A redacted TextField hides its text as a SecureField does")
struct RedactedTextFieldTests {
    @Test("Its text is drawn a glyph a character, spaces and wide characters included", arguments: FieldHiding.allCases)
    func drawsNoText(hiding: FieldHiding) {
        for vertical in [false, true] {
            let (app, _, _) = fieldApp(hiding, "hi 世界", vertical: vertical)
            let screen = app.screen.text
            if hiding.hides {
                #expect(!screen.contains("hi") && !screen.contains("世"), "vertical \(vertical): \(screen)")
                // Five characters, five cells: no space shows where the
                // words break, and no wide character takes two.
                let mask = String(repeating: hiding.glyph, count: 5)
                #expect(screen.contains(mask + " ") || screen.contains(mask + "▐"), "vertical \(vertical): \(screen)")
                #expect(!screen.contains(String(repeating: hiding.glyph, count: 6)), "\(screen)")
            } else {
                #expect(screen.contains("hi 世界"), "vertical \(vertical): \(screen)")
            }
        }
    }

    @Test("Its prompt is a skeleton too", arguments: FieldHiding.allCases)
    func promptRedacted(hiding: FieldHiding) {
        let (app, _, _) = fieldApp(hiding, "")
        #expect(app.screen.contains("Name") == !hiding.hides, "\(app.screen.text)")
    }

    @Test("Copy and cut put nothing on the clipboard and take nothing away", arguments: FieldHiding.allCases)
    func noCopyOrCut(hiding: FieldHiding) {
        let (app, text, board) = fieldApp(hiding, "hunter2")
        app.press(.home, modifiers: .shift)
        app.press(.character("c"), modifiers: .control)
        app.press(.character("x"), modifiers: .control)
        if hiding.hides {
            #expect(board.writes.isEmpty, "\(board.writes)")
            #expect(text.value == "hunter2")
        } else {
            #expect(board.writes == ["hunter2", "hunter2"])
            #expect(text.value.isEmpty)
        }
    }

    @Test("Ctrl-K keeps no kill for Ctrl-Y", arguments: FieldHiding.allCases)
    func noKill(hiding: FieldHiding) {
        let (app, text, _) = fieldApp(hiding, "hunter2")
        app.press(.left, times: 3)
        app.press(.character("k"), modifiers: .control)
        app.press(.home)
        app.press(.character("y"), modifiers: .control)
        #expect(text.value == (hiding.hides ? "hunt" : "er2hunt"))
    }

    @Test("A word motion and a word deletion go one character", arguments: FieldHiding.allCases)
    func wordMotionByCharacter(hiding: FieldHiding) {
        let (app, text, _) = fieldApp(hiding, "hunter2 abc")
        app.press(.left, modifiers: .option)
        app.type("X")
        #expect(text.value == (hiding.hides ? "hunter2 abXc" : "hunter2 Xabc"))

        // Option-Backspace, from the end.
        let (deleting, deleted, _) = fieldApp(hiding, "hunter2 abc")
        deleting.press(.backspace, modifiers: .option)
        #expect(deleted.value == (hiding.hides ? "hunter2 ab" : "hunter2 "))
    }

    @Test("A double-click selects all of the text, not the word under it", arguments: FieldHiding.allCases)
    func doubleClickSelectsAll(hiding: FieldHiding) throws {
        let (app, text, _) = fieldApp(hiding, "hunter2 abc")
        // The first character's cell: the glyph's, or the letter's.
        let first = try #require(app.screen.location(of: hiding.hides ? String(hiding.glyph) : "h"))
        app.click(at: first)
        app.click(at: first)
        app.type("X")
        #expect(text.value == (hiding.hides ? "X" : "X abc"))
    }
}
