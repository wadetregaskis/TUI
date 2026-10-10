//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameworkStringLookupTests.swift
//
//  Who is asking decides the order (A14, owner decision 2026-10-05): TUIkit's
//  own words are changed by an app only on purpose — registered strings or a
//  table it names `TUIkit` — never by its `Localizable` table spelling the
//  same key, except where TUIkit has no translation of the key in the
//  language, when the app's words are better than none. The app's own keys
//  read its strings first and may borrow TUIkit's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitPresentation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

@MainActor
@Suite("TUIkit's own words and the app's keys")
final class FrameworkStringLookupTests {
    let configDir = NSTemporaryDirectory() + "tuikit-loc-\(UUID().uuidString)"

    deinit {
        try? FileManager.default.removeItem(atPath: configDir)
    }

    private func service(_ files: TableBundle, environment: [String: String] = [:]) -> LocalizationService {
        LocalizationService(configDirectoryPath: configDir, defaultBundle: files.bundle, environment: environment)
    }

    /// The text `view` draws, through `service` in the environment.
    private func rendered(_ view: some View, with service: LocalizationService) -> String {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 20, availableHeight: 1, environment: environment, tuiContext: tui)
        return renderToBuffer(view.environment(\.localizationService, service), context: context)
            .lines.joined().stripped.trimmingCharacters(in: .whitespaces)
    }

    // MARK: TUIkit's own words

    /// The accident the order exists to prevent: an app whose `Localizable`
    /// table happens to spell one of TUIkit's keys changed TUIkit's own
    /// controls in a language TUIkit translates.
    @Test("An app's Localizable table does not change TUIkit's own word in a language TUIkit translates")
    func theAppsTableLeavesTUIkitsWordsAlone() throws {
        let files = try TableBundle([
            "de": ["Localizable": ["button.cancel": "Nö"]],
            "en": ["Localizable": ["button.cancel": "Nah"]],
        ])
        let service = service(files)
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Abbrechen", "the app's table changed TUIkit's German")
        #expect(rendered(LocalizedString(LocalizationKey.Button.cancel), with: service) == "Abbrechen")
        // The app's own lookup of the same key reads its own table.
        #expect(service.string(for: "button.cancel") == "Nö")
        #expect(rendered(LocalizedString("button.cancel"), with: service) == "Nö")
        service.pinLanguageForTesting(.english)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Cancel", "the app's table changed TUIkit's English")
        #expect(service.string(for: "button.cancel") == "Nah")
    }

    /// The owner's rule: a language TUIkit does not ship gets the app's words
    /// for TUIkit's keys, in that language, before English.
    @Test("A Portuguese app's Localizable table gives TUIkit's words in Portuguese, and English only for the rest")
    func aLanguageTUIkitDoesNotShipReadsTheAppsTable() throws {
        let files = try TableBundle([
            "pt": ["Localizable": ["button.ok": "Certo", "label.warning": "Aviso"]],
            "en": ["Localizable": ["button.ok": "Okey-dokey"]],
        ])
        let service = service(files, environment: ["LANG": "pt_BR.UTF-8"])
        #expect(service.currentLanguage == .english, "TUIkit ships no Portuguese of its own")
        #expect(service.lookupLanguageCodes == ["pt", "en"])
        #expect(service.string(for: LocalizationKey.Button.ok) == "Certo")
        #expect(rendered(LocalizedString(LocalizationKey.Button.ok), with: service) == "Certo")
        // A preset alert's default title is TUIkit's word too.
        let title = LocalizedStringKey(LocalizationKey.Label.warning.rawValue)
        #expect(title.localizedTitle(defaultingTo: .warning, service: service) == "Aviso")
        // What the app does not spell in Portuguese is TUIkit's English.
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Cancel")
        // The app's own keys read Portuguese first too.
        #expect(service.string(for: "button.ok") == "Certo")
    }

    /// The other half of the rule: a key missing from a language TUIkit does
    /// ship — here an appearance the app added, whose `appearance.*` key
    /// TUIkit has in no language — is read from the app's table in the app's
    /// language before English.
    @Test("Where TUIkit has no translation of its key, the app's Localizable table is read before English")
    func theAppsTableFillsTUIkitsGaps() throws {
        let files = try TableBundle([
            "de": ["Localizable": ["appearance.paper": "Papier"]],
            "en": ["Localizable": ["appearance.paper": "Paper"]],
        ])
        let service = service(files)
        service.pinLanguageForTesting(.german)
        #expect(service.frameworkString(for: "appearance.paper") == "Papier")
        service.pinLanguageForTesting(.french)
        #expect(service.frameworkString(for: "appearance.paper") == "Paper")
    }

    @Test("A table the app names TUIkit changes TUIkit's own words, in any language")
    func aTUIkitTableOverridesTUIkitsWords() throws {
        let files = try TableBundle([
            "en": ["TUIkit": ["button.cancel": "Never mind"]],
            "de": ["TUIkit": ["button.cancel": "Lieber nicht"]],
            "ja": ["TUIkit": ["button.cancel": "やめる"]],
            "pt": ["TUIkit": ["button.cancel": "Deixa"]],
        ])
        let service = service(files)
        service.pinLanguageForTesting(.english)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Never mind")
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Lieber nicht")
        service.pinLanguageForTesting(.japanese)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "やめる")
        // A language the table does not hold keeps TUIkit's own word.
        service.pinLanguageForTesting(.french)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Annuler")
        // And one TUIkit does not ship.
        let portuguese = self.service(files, environment: ["LANG": "pt_PT.UTF-8"])
        #expect(portuguese.string(for: LocalizationKey.Button.cancel) == "Deixa")
    }

    @Test("Registered strings change TUIkit's own words as before, ahead of a TUIkit table")
    func registeredStringsOverrideTUIkitsWords() throws {
        let files = try TableBundle(["de": ["TUIkit": ["button.ok": "Tabelle"]]])
        let service = service(files)
        service.pinLanguageForTesting(.german)
        #expect(service.string(for: LocalizationKey.Button.ok) == "Tabelle")
        service.register(translations: ["de": ["button.ok": "Gut"]])
        #expect(service.string(for: LocalizationKey.Button.ok) == "Gut")
    }

    // MARK: The app's own keys

    /// The review's inconsistency: naming the default table made it a named
    /// table, which is read ahead of the registered strings, so the same call
    /// written two ways found two different strings. SwiftUI reads them as one.
    @Test("Writing out the default table and bundle resolves exactly as leaving them off")
    func theDefaultWrittenOutIsTheDefault() throws {
        let files = try TableBundle(["en": ["Localizable": ["greeting": "Table"]]])
        let service = service(files)
        service.pinLanguageForTesting(.english)
        service.register(translations: ["en": ["greeting": "Registered"]])
        #expect(service.string(for: "greeting") == "Registered")
        #expect(service.string(for: "greeting", tableName: "Localizable", bundle: nil) == "Registered")
        #expect(service.string(for: "greeting", tableName: nil, bundle: files.bundle) == "Registered")
        #expect(service.string(for: "greeting", tableName: "Localizable", bundle: files.bundle) == "Registered")
    }

    @Test("An app's key reads the named table, then registered strings, then Localizable, then TUIkit's")
    func theAppsKeyOrder() throws {
        let files = try TableBundle([
            "en": [
                "Localizable": ["greeting": "Hello", "both": "From Localizable"],
                "Onboarding": ["welcome": "Welcome aboard"],
            ]
        ])
        let service = service(files)
        service.pinLanguageForTesting(.english)
        service.register(translations: ["en": ["both": "Registered"]])
        #expect(service.string(for: "welcome", tableName: "Onboarding", bundle: nil) == "Welcome aboard")
        #expect(service.string(for: "both", tableName: "Onboarding", bundle: nil) == "Registered")
        #expect(service.string(for: "greeting", tableName: "Onboarding", bundle: nil) == "Hello")
        // An app borrows TUIkit's translation of a key it does not spell.
        #expect(service.string(for: "button.cancel", tableName: "Onboarding", bundle: nil) == "Cancel")
    }

    // MARK: Which languages

    @Test("The environment's languages ahead of the first TUIkit ships are looked up first")
    func languagesAheadOfTUIkitsAreKept() {
        #expect(LocalizationService.systemPreferredLanguageCodes(environment: ["LANG": "pt_BR.UTF-8"], preferredLanguages: []) == ["pt"])
        #expect(
            LocalizationService.systemPreferredLanguageCodes(
                environment: ["LANG": "pt_BR.UTF-8"], preferredLanguages: ["fr-FR"]) == ["pt", "fr"])
        #expect(
            LocalizationService.systemPreferredLanguageCodes(environment: ["LANGUAGE": "pt:es:fr"], preferredLanguages: [])
                == ["pt", "es"])
        #expect(
            LocalizationService.systemPreferredLanguageCodes(environment: [:], preferredLanguages: ["pt-BR", "de-DE", "fr"])
                == ["pt", "de"])
        // A three-letter code is a language of its own, not the two-letter
        // one it begins with: Filipino is not Finnish.
        #expect(LocalizationService.systemPreferredLanguageCodes(environment: ["LANG": "fil_PH"], preferredLanguages: []) == ["fil"])
        #expect(LocalizationService.systemPreferredLanguageCodes(environment: ["LC_ALL": "C.UTF-8"], preferredLanguages: []).isEmpty)

        let service = LocalizationService(
            configDirectoryPath: configDir, environment: ["LANGUAGE": "pt:es", "LANG": "de_DE.UTF-8"])
        #expect(service.currentLanguage == .spanish)
        #expect(service.lookupLanguageCodes == ["pt", "es", "en"])
        service.pinLanguageForTesting(.german)
        #expect(service.lookupLanguageCodes == ["de", "en"], "a language chosen in the app is not the environment's")
    }
}
