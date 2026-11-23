//  🖥️ TUI — A Terminal UI framework for Swift
//  UndoTitleTests.swift
//
//  An Undo or Redo title with a step's name is joined as Foundation's
//  `UndoManager` joins it on macOS, in each of TUI's languages: what the
//  platforms without one, and the menu bar everywhere, show (hunt FENV-15).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings

@Suite("Undo and Redo titles")
struct UndoTitleTests {
    /// `UndoManager().undoMenuTitle(forUndoActionName: "XYZ")` and its redo
    /// twin on macOS 15 (Darwin 24.6), run once per language with
    /// `-AppleLanguages`, 2026-11-23: Foundation's `Undo.loctable`. The bare
    /// verbs are its `Undo` and `Redo`.
    private static let appKit: [(locale: String, undo: String, redo: String, bareUndo: String, bareRedo: String)] = [
        ("en_US", "Undo XYZ", "Redo XYZ", "Undo", "Redo"),
        ("de_DE", "XYZ widerrufen", "XYZ wiederholen", "Widerrufen", "Wiederholen"),
        ("es_ES", "Deshacer XYZ", "Rehacer XYZ", "Deshacer", "Rehacer"),
        ("fr_FR", "Annuler XYZ", "Rétablir XYZ", "Annuler", "Rétablir"),
        ("it_IT", "Annulla XYZ", "Ripristina XYZ", "Annulla", "Ripristina"),
        ("ja_JP", "取り消す- XYZ", "やり直す- XYZ", "取り消す", "やり直す"),
        ("zh_CN", "撤销XYZ", "重做XYZ", "撤销", "重做"),
    ]

    /// A service in `locale`'s language, with a config directory of its own,
    /// so nothing reads or writes a real language preference.
    private func service(_ locale: String) -> LocalizationService {
        LocalizationService(
            configDirectoryPath: NSTemporaryDirectory() + "tuikit-undo-titles-\(UUID().uuidString)",
            environment: ["LANG": "\(locale).UTF-8"])
    }

    @Test("A named step's title is Foundation's, word for word, in every language")
    func namedStep() {
        #expect(Self.appKit.count == LocalizationService.Language.allCases.count)
        for expected in Self.appKit {
            let service = service(expected.locale)
            #expect(service.undoMenuTitle(forUndoActionName: "XYZ") == expected.undo, "\(expected.locale)")
            #expect(service.redoMenuTitle(forUndoActionName: "XYZ") == expected.redo, "\(expected.locale)")
        }
    }

    @Test("A step with no name is titled with the verb alone, Foundation's own")
    func unnamedStep() {
        for expected in Self.appKit {
            let service = service(expected.locale)
            #expect(service.undoMenuTitle(forUndoActionName: "") == expected.bareUndo, "\(expected.locale)")
            #expect(service.redoMenuTitle(forUndoActionName: "") == expected.bareRedo, "\(expected.locale)")
        }
    }

    @Test("The step's name is put in as given, even where it holds a placeholder")
    func nameIsVerbatim() {
        let service = service("de_DE")
        #expect(service.undoMenuTitle(forUndoActionName: "100 %@") == "100 %@ widerrufen")
    }
}
