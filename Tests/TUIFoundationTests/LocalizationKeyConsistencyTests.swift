//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationKeyConsistencyTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings
@testable import TUITestSupport

// MARK: - Localization Key Consistency Tests

/// Validates that all LocalizationKey enums match the actual translation files.
///
/// These tests ensure:
/// 1. Every key in the enum exists in the English translation file
/// 2. No extra keys are in the translation files that don't exist in the enum
/// 3. All enum keys are actually used (no dead code)
@Suite("LocalizationKeyConsistency")
final class LocalizationKeyConsistencyTests {
    private var englishTranslations: [String: String] = [:]

    init() {
        self.englishTranslations = Self.loadTranslations()
    }

    // MARK: - Helper Method

    private static func loadTranslations() -> [String: String] {
        // Try to load from the main framework bundle first (for production)
        var url = Bundle.module.url(
            forResource: "en",
            withExtension: "json",
            subdirectory: "translations"
        )

        // If not found, try to load from the project directory (for tests)
        if url == nil {
            let projectPath = FileManager.default.currentDirectoryPath
            let sourcePath = (projectPath as NSString).appendingPathComponent(
                "Sources/TUIStrings/Localization/translations/en.json"
            )
            if FileManager.default.fileExists(atPath: sourcePath) {
                url = URL(fileURLWithPath: sourcePath)
            }
        }

        guard let url else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let dict =
                try JSONSerialization.jsonObject(
                    with: data,
                    options: .fragmentsAllowed
                ) as? [String: String]
            return dict ?? [:]
        } catch {
            return [:]
        }
    }

    /// Loads a specific language's translation table (bundle first, then source).
    private static func loadTranslations(language code: String) -> [String: String] {
        var url = Bundle.module.url(
            forResource: code, withExtension: "json", subdirectory: "translations")
        if url == nil {
            let sourcePath = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent("Sources/TUIStrings/Localization/translations/\(code).json")
            if FileManager.default.fileExists(atPath: sourcePath) {
                url = URL(fileURLWithPath: sourcePath)
            }
        }
        guard let url, let data = try? Data(contentsOf: url),
            let dict = try? JSONSerialization.jsonObject(
                with: data, options: .fragmentsAllowed) as? [String: String]
        else { return [:] }
        return dict
    }

    // MARK: - Cross-language parity

    @Test("Every language file has exactly the English key set")
    func everyLanguageHasEnglishKeys() {
        let englishKeys = Set(englishTranslations.keys)
        #expect(!englishKeys.isEmpty, "English translations failed to load")
        for language in LocalizationService.Language.allCases where language != .english {
            let keys = Set(Self.loadTranslations(language: language.rawValue).keys)
            let missing = englishKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(englishKeys).sorted()
            #expect(
                keys == englishKeys,
                "\(language.rawValue).json differs from en.json — missing: \(missing); extra: \(extra)")
        }
    }

    // MARK: - Button Key Tests

    @Test("All button keys exist in translations")
    func allButtonKeysExist() {
        let keys = [
            LocalizationKey.Button.ok,
            LocalizationKey.Button.cancel,
            LocalizationKey.Button.yes,
            LocalizationKey.Button.no,
            LocalizationKey.Button.save,
            LocalizationKey.Button.delete,
            LocalizationKey.Button.close,
            LocalizationKey.Button.apply,
            LocalizationKey.Button.reset,
            LocalizationKey.Button.submit,
            LocalizationKey.Button.search,
            LocalizationKey.Button.clear,
            LocalizationKey.Button.add,
            LocalizationKey.Button.remove,
            LocalizationKey.Button.edit,
            LocalizationKey.Button.done,
            LocalizationKey.Button.next,
            LocalizationKey.Button.previous,
            LocalizationKey.Button.back,
            LocalizationKey.Button.forward,
            LocalizationKey.Button.refresh,
            LocalizationKey.Button.rename,
            LocalizationKey.Button.paste,
            LocalizationKey.Button.copy,
            LocalizationKey.Button.replace,
            LocalizationKey.Button.replaceAll,
            LocalizationKey.Button.create,
        ]

        for key in keys {
            #expect(englishTranslations[key.rawValue] != nil, "Button key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Label Key Tests

    @Test("All label keys exist in translations")
    func allLabelKeysExist() {
        // `allCases`, not a written-out list — see `allStatusBarKeysExist`.
        for key in LocalizationKey.Label.allCases {
            #expect(
                englishTranslations[key.rawValue] != nil,
                "Label key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Error Key Tests

    @Test("All error keys exist in translations")
    func allErrorKeysExist() {
        let keys = [
            LocalizationKey.Error.invalidInput,
            LocalizationKey.Error.requiredField,
            LocalizationKey.Error.notFound,
            LocalizationKey.Error.accessDenied,
            LocalizationKey.Error.networkError,
            LocalizationKey.Error.unknown,
            LocalizationKey.Error.invalidFormat,
            LocalizationKey.Error.operationFailed,
            LocalizationKey.Error.timeout,
            LocalizationKey.Error.fileNotFound,
            LocalizationKey.Error.permissionDenied,
        ]

        for key in keys {
            #expect(englishTranslations[key.rawValue] != nil, "Error key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Placeholder Key Tests

    @Test("All placeholder keys exist in translations")
    func allPlaceholderKeysExist() {
        let keys = [
            LocalizationKey.Placeholder.search,
            LocalizationKey.Placeholder.enterText,
            LocalizationKey.Placeholder.enterValue,
            LocalizationKey.Placeholder.selectOption,
            LocalizationKey.Placeholder.enterName,
            LocalizationKey.Placeholder.chooseFile,
        ]

        for key in keys {
            #expect(englishTranslations[key.rawValue] != nil, "Placeholder key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Menu Key Tests

    @Test("All menu keys exist in translations")
    func allMenuKeysExist() {
        // Enumerated, as the status bar's are: the menu bar (lane O13) grew
        // the group, and a hand-written list stops covering what it omits.
        for key in LocalizationKey.Menu.allCases {
            #expect(englishTranslations[key.rawValue] != nil, "Menu key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Dialog Key Tests

    @Test("All dialog keys exist in translations")
    func allDialogKeysExist() {
        let keys = [
            LocalizationKey.Dialog.confirm,
            LocalizationKey.Dialog.deleteConfirmation,
            LocalizationKey.Dialog.unsavedChanges,
            LocalizationKey.Dialog.overwriteConfirmation,
            LocalizationKey.Dialog.exitConfirmation,
            LocalizationKey.Dialog.success,
            LocalizationKey.Dialog.error,
        ]

        for key in keys {
            #expect(englishTranslations[key.rawValue] != nil, "Dialog key '\(key.rawValue)' not found in translations")
        }
    }

    // MARK: - Validation Key Tests

    @Test("All validation keys exist in translations")
    func allValidationKeysExist() {
        let keys = [
            LocalizationKey.Validation.emailInvalid,
            LocalizationKey.Validation.passwordTooShort,
            LocalizationKey.Validation.usernameTaken,
            LocalizationKey.Validation.fieldRequired,
        ]

        for key in keys {
            #expect(englishTranslations[key.rawValue] != nil, "Validation key '\(key.rawValue)' not found in translations")
        }
    }

    @Test("All status bar keys exist in translations")
    func allStatusBarKeysExist() {
        // `allCases` rather than a written-out list, so a key added to the enum
        // is covered here the moment it exists rather than the moment somebody
        // remembers to add it. This group is the framework's OWN words — the
        // verbs it publishes for Return and Escape — so a missing entry shows
        // up as English in a translated app, which is what it did.
        for key in LocalizationKey.StatusBar.allCases {
            #expect(
                englishTranslations[key.rawValue] != nil,
                "Status bar key '\(key.rawValue)' not found in translations")
        }
    }

    /// The two menu verbs are templates, and a translation that drops the
    /// placeholder loses the noun entirely rather than misplacing it.
    @Test("The menu verb templates keep their placeholder in every language")
    func menuTemplatesKeepPlaceholder() {
        for language in LocalizationService.Language.allCases {
            let table = Self.loadTranslations(language: language.rawValue)
            for key in [
                LocalizationKey.StatusBar.openMenu, LocalizationKey.StatusBar.closeMenu,
            ] {
                let template = table[key.rawValue]
                #expect(
                    template?.contains("%@") == true,
                    "\(language.rawValue).json '\(key.rawValue)' must carry %@, got \(template ?? "nil")")
            }
        }
    }

    // MARK: - Coverage Tests

    @Test("No extraneous keys in translations")
    func noExtraneousKeys() {
        // Collect all known enum keys
        var enumKeys = Set<String>()

        // Button keys
        enumKeys.insert(LocalizationKey.Button.ok.rawValue)
        enumKeys.insert(LocalizationKey.Button.cancel.rawValue)
        enumKeys.insert(LocalizationKey.Button.yes.rawValue)
        enumKeys.insert(LocalizationKey.Button.no.rawValue)
        enumKeys.insert(LocalizationKey.Button.save.rawValue)
        enumKeys.insert(LocalizationKey.Button.delete.rawValue)
        enumKeys.insert(LocalizationKey.Button.close.rawValue)
        enumKeys.insert(LocalizationKey.Button.apply.rawValue)
        enumKeys.insert(LocalizationKey.Button.reset.rawValue)
        enumKeys.insert(LocalizationKey.Button.submit.rawValue)
        enumKeys.insert(LocalizationKey.Button.search.rawValue)
        enumKeys.insert(LocalizationKey.Button.clear.rawValue)
        enumKeys.insert(LocalizationKey.Button.add.rawValue)
        enumKeys.insert(LocalizationKey.Button.remove.rawValue)
        enumKeys.insert(LocalizationKey.Button.edit.rawValue)
        enumKeys.insert(LocalizationKey.Button.done.rawValue)
        enumKeys.insert(LocalizationKey.Button.next.rawValue)
        enumKeys.insert(LocalizationKey.Button.previous.rawValue)
        enumKeys.insert(LocalizationKey.Button.back.rawValue)
        enumKeys.insert(LocalizationKey.Button.forward.rawValue)
        enumKeys.insert(LocalizationKey.Button.refresh.rawValue)
        enumKeys.insert(LocalizationKey.Button.rename.rawValue)
        enumKeys.insert(LocalizationKey.Button.paste.rawValue)
        enumKeys.insert(LocalizationKey.Button.copy.rawValue)
        enumKeys.insert(LocalizationKey.Button.replace.rawValue)
        enumKeys.insert(LocalizationKey.Button.replaceAll.rawValue)
        enumKeys.insert(LocalizationKey.Button.create.rawValue)

        // Label keys
        for key in LocalizationKey.Label.allCases {
            enumKeys.insert(key.rawValue)
        }

        // Error keys
        enumKeys.insert(LocalizationKey.Error.invalidInput.rawValue)
        enumKeys.insert(LocalizationKey.Error.requiredField.rawValue)
        enumKeys.insert(LocalizationKey.Error.notFound.rawValue)
        enumKeys.insert(LocalizationKey.Error.accessDenied.rawValue)
        enumKeys.insert(LocalizationKey.Error.networkError.rawValue)
        enumKeys.insert(LocalizationKey.Error.unknown.rawValue)
        enumKeys.insert(LocalizationKey.Error.invalidFormat.rawValue)
        enumKeys.insert(LocalizationKey.Error.operationFailed.rawValue)
        enumKeys.insert(LocalizationKey.Error.timeout.rawValue)
        enumKeys.insert(LocalizationKey.Error.fileNotFound.rawValue)
        enumKeys.insert(LocalizationKey.Error.permissionDenied.rawValue)

        // Placeholder keys
        enumKeys.insert(LocalizationKey.Placeholder.search.rawValue)
        enumKeys.insert(LocalizationKey.Placeholder.enterText.rawValue)
        enumKeys.insert(LocalizationKey.Placeholder.enterValue.rawValue)
        enumKeys.insert(LocalizationKey.Placeholder.selectOption.rawValue)
        enumKeys.insert(LocalizationKey.Placeholder.enterName.rawValue)
        enumKeys.insert(LocalizationKey.Placeholder.chooseFile.rawValue)

        // Menu keys — enumerated, as the status bar's are.
        for key in LocalizationKey.Menu.allCases {
            enumKeys.insert(key.rawValue)
        }

        // Dialog keys
        enumKeys.insert(LocalizationKey.Dialog.confirm.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.deleteConfirmation.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.unsavedChanges.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.overwriteConfirmation.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.exitConfirmation.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.success.rawValue)
        enumKeys.insert(LocalizationKey.Dialog.error.rawValue)

        // Validation keys
        enumKeys.insert(LocalizationKey.Validation.emailInvalid.rawValue)
        enumKeys.insert(LocalizationKey.Validation.passwordTooShort.rawValue)
        enumKeys.insert(LocalizationKey.Validation.usernameTaken.rawValue)
        enumKeys.insert(LocalizationKey.Validation.fieldRequired.rawValue)

        // Appearance keys
        enumKeys.insert(LocalizationKey.Appearance.rounded.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.line.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.doubleLine.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.heavy.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.braille.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.braille2.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.block.rawValue)
        enumKeys.insert(LocalizationKey.Appearance.blank.rawValue)

        // Control style names — enumerated, as the status bar's are.
        for key in LocalizationKey.ControlStyle.allCases {
            enumKeys.insert(key.rawValue)
        }

        // Status bar keys — enumerated, not restated. The hand-written list
        // here covered three of them and silently stopped covering the rest as
        // the group grew.
        for key in LocalizationKey.StatusBar.allCases {
            enumKeys.insert(key.rawValue)
        }

        // A span's year and month names — enumerated, as the status bar's are.
        for key in LocalizationKey.TimeSpan.allCases {
            enumKeys.insert(key.rawValue)
        }

        // The keys named by a word rather than a symbol (the space bar).
        for key in LocalizationKey.KeyName.allCases {
            enumKeys.insert(key.rawValue)
        }

        // The file panels' words — enumerated, as the status bar's are.
        for key in LocalizationKey.FilePanel.allCases {
            enumKeys.insert(key.rawValue)
        }

        // What an app with no terminal says — enumerated, as the status bar's are.
        for key in LocalizationKey.NoTerminal.allCases {
            enumKeys.insert(key.rawValue)
        }

        // Check for extraneous keys
        let translationKeys = Set(englishTranslations.keys)
        let extraneousKeys = translationKeys.subtracting(enumKeys)

        #expect(extraneousKeys.isEmpty, "Found keys in translations that don't exist in LocalizationKey enum: \(extraneousKeys.sorted())")
    }

    @Test("All enum keys are covered in translations")
    func allEnumKeysCovered() {
        // button + label + error + placeholder + menu + dialog + validation
        //   + statusbar + appearance + time span + key names + file panels + control styles
        let expectedKeyCount =
            27 + LocalizationKey.Label.allCases.count + 11 + 6 + LocalizationKey.Menu.allCases.count + 7 + 4
            + LocalizationKey.StatusBar.allCases.count + 8 + LocalizationKey.TimeSpan.allCases.count
            + LocalizationKey.KeyName.allCases.count + LocalizationKey.FilePanel.allCases.count
            + LocalizationKey.ControlStyle.allCases.count + LocalizationKey.NoTerminal.allCases.count
        #expect(
            englishTranslations.count == expectedKeyCount,
            "Expected \(expectedKeyCount) keys in translations, but got \(englishTranslations.count)"
        )
    }

    @Test("Translation file is valid JSON")
    func translationFileIsValid() {
        #expect(!englishTranslations.isEmpty, "English translations could not be loaded")
        #expect(!englishTranslations.isEmpty, "English translations are empty")
    }
}
