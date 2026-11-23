//  🖥️ TUI — A Terminal UI framework for Swift
//  LanguageScriptAndRegionTests.swift
//
//  A language is told apart by its script: TUI's Chinese is Simplified, so a
//  reader of Traditional Chinese (`zh_TW`, `zh-Hant`) is not given it, and
//  reads the app's own Traditional strings and then the next language they
//  name (hunt TOOLS-10). And a key is read under a language's full tag first,
//  then its bare one, everywhere: the environment's languages, a subtree's
//  `\.locale`, the app's registrations and folders (the owner's O-06 (a),
//  2026-11-21; hunt FENV-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@Suite("Languages told apart by script and region")
final class LanguageScriptAndRegionTests {
    let configDir = NSTemporaryDirectory() + "tuikit-h54-\(UUID().uuidString)"

    deinit {
        try? FileManager.default.removeItem(atPath: configDir)
    }

    // MARK: - Reading a tag

    @Test("A locale name or tag is read as its language, with the script only where it tells the language apart")
    func tags() {
        func bare(_ name: String) -> String? { LanguageTag(name)?.bare }
        #expect(bare("zh_TW.UTF-8") == "zh-Hant", "Taiwan's Chinese is Traditional")
        #expect(bare("zh-Hant-TW") == "zh-Hant")
        #expect(bare("zh_HK") == "zh-Hant")
        #expect(bare("zh-Hant") == "zh-Hant")
        #expect(bare("zh-Hans-TW") == "zh", "a script stated wins over the region's")
        #expect(bare("zh_CN.UTF-8") == "zh")
        #expect(bare("zh-Hans") == "zh")
        #expect(bare("zh") == "zh")
        #expect(bare("de_DE.UTF-8@euro") == "de", "never de-Latn")
        #expect(bare("sr-Latn") == "sr-Latn", "Serbian's own script is Cyrillic")
        #expect(bare("fil_PH") == "fil", "a three-letter code is a language of its own")
        #expect(bare("C") == nil)
        #expect(bare("POSIX") == nil)
        #expect(bare("C.UTF-8") == nil)
        #expect(bare("") == nil)
    }

    // MARK: - The environment

    @Test("A reader of Traditional Chinese is not given TUI's Simplified table, and the walk goes on")
    func traditionalChineseIsNotSimplified() {
        let detected = LocalizationService.systemPreferredLanguage
        #expect(detected(["LANG": "zh_TW.UTF-8"], []) == nil)
        #expect(detected(["LANG": "zh_HK.UTF-8"], ["en-001"]) == .english)
        #expect(detected([:], ["zh-Hant-TW", "ja"]) == .japanese)
        #expect(detected([:], ["zh-Hant", "de-DE"]) == .german)
        #expect(detected(["LANG": "zh_CN.UTF-8"], []) == .simplifiedChinese)
        #expect(detected([:], ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(
            LocalizationService.systemPreferredLanguageCodes(environment: ["LANG": "zh_TW.UTF-8"], preferredLanguages: ["ja"])
                == ["zh-Hant-TW", "ja"])
    }

    @Test("A Traditional Chinese user reads TUI's words in English, and the app's Traditional strings first")
    func traditionalChineseService() throws {
        let files = try TableBundle([
            "en": ["Localizable": ["greeting": "Hello"]],
            "zh-Hans": ["Localizable": ["greeting": "你好-简"]],
            "zh-Hant": ["Localizable": ["greeting": "你好-繁"]],
        ])
        let service = LocalizationService(
            configDirectoryPath: configDir, defaultBundle: files.bundle, environment: ["LANG": "zh_TW.UTF-8"])
        #expect(service.currentLanguage == .english)
        #expect(service.lookupLanguageCodes == ["zh-Hant-TW", "zh-Hant", "en"])
        #expect(service.frameworkString(for: "button.cancel") == "Cancel", "TUI's Simplified table was read")
        #expect(service.string(for: "greeting") == "你好-繁")
        service.registerWithoutRendering(translations: ["zh-Hant": ["test.h54.registered": "註冊"], "zh": ["test.h54.registered": "注册"]])
        #expect(service.string(for: "test.h54.registered") == "註冊")
    }

    @Test("Time spans' years and months follow the same rule")
    func timeSpans() {
        #expect(TimeSpanLanguage(Locale(identifier: "zh_TW")).language == .english)
        #expect(
            TimeSpanLanguage(Locale(languageCode: "zh", script: .hanSimplified, languageRegion: "TW")).language
                == .simplifiedChinese, "Simplified Chinese written for Taiwan is Simplified")
    }

    // MARK: - Full tag, then bare (O-06 (a))

    @Test("A tag is read under its full form first, then its bare one")
    func lookupCodes() {
        #expect(LanguageTag("pt_BR.UTF-8")?.lookupCodes == ["pt-BR", "pt"])
        #expect(LanguageTag("zh_TW.UTF-8")?.lookupCodes == ["zh-Hant-TW", "zh-Hant"], "never zh, which is Simplified")
        #expect(LanguageTag("zh-Hans-CN")?.lookupCodes == ["zh-CN", "zh"])
        #expect(LanguageTag("zh-Hans-TW")?.lookupCodes == ["zh-Hans-TW", "zh"])
        #expect(LanguageTag("de")?.lookupCodes == ["de"])
        #expect(LanguageTag("en_001")?.lookupCodes == ["en"], "the world region is no region")
        #expect(LanguageTag("es_419")?.lookupCodes == ["es-419", "es"])
    }

    @Test("The environment's languages are looked up by full tag, then bare, and the app's registrations by any spelling")
    func regionalRegistrations() {
        let detected = LocalizationService.systemPreferredLanguageCodes
        #expect(detected(["LANG": "pt_BR.UTF-8"], ["fr-FR"]) == ["pt-BR", "fr-FR"])
        #expect(detected([:], ["de-DE", "en-US"]) == ["de-DE"])

        let brazil = LocalizationService(configDirectoryPath: configDir, environment: ["LANG": "pt_BR.UTF-8"])
        let portugal = LocalizationService(configDirectoryPath: configDir, environment: ["LANG": "pt_PT.UTF-8"])
        #expect(brazil.lookupLanguageCodes == ["pt-BR", "pt", "en"])
        #expect(portugal.lookupLanguageCodes == ["pt-PT", "pt", "en"])
        let translations = [
            "pt_BR": ["test.h54.bus": "ônibus"], "pt-PT": ["test.h54.bus": "autocarro"],
            "pt": ["test.h54.bus": "autocarro", "test.h54.hello": "olá"], "en": ["test.h54.bus": "bus"],
        ]
        for service in [brazil, portugal] { service.registerWithoutRendering(translations: translations) }
        #expect(brazil.string(for: "test.h54.bus") == "ônibus")
        #expect(portugal.string(for: "test.h54.bus") == "autocarro")
        #expect(brazil.string(for: "test.h54.hello") == "olá", "the bare language after the full tag")
        #expect(brazil.currentLocale.identifier.hasPrefix("pt"), "\(brazil.currentLocale.identifier)")
        #expect(brazil.currentLocale.region?.identifier == "BR")
    }

    @Test("An app's regional folders are read before its bare one")
    func regionalFolders() throws {
        let files = try TableBundle([
            "en": ["Localizable": ["bus": "bus", "hello": "hello"]],
            "pt": ["Localizable": ["bus": "autocarro", "hello": "olá"]],
            "pt-BR": ["Localizable": ["bus": "ônibus"]],
            "pt-PT": ["Localizable": ["bus": "autocarro (PT)"]],
        ])
        let brazil = LocalizationService(
            configDirectoryPath: configDir, defaultBundle: files.bundle, environment: ["LANG": "pt_BR.UTF-8"])
        let portugal = LocalizationService(
            configDirectoryPath: configDir, defaultBundle: files.bundle, environment: ["LANG": "pt_PT.UTF-8"])
        #expect(brazil.string(for: "bus") == "ônibus")
        #expect(portugal.string(for: "bus") == "autocarro (PT)")
        #expect(brazil.string(for: "hello") == "olá")
        let match = BundleStringTables.localization(for:among:)
        #expect(match("pt-BR", ["en", "pt", "pt_BR", "pt-PT"]) == "pt_BR")
        #expect(match("pt", ["en", "pt_BR", "pt"]) == "pt")
    }

    @Test("A subtree's locale carries its script and region")
    func subtreeLanguage() {
        func language(_ identifier: String) -> String? {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: identifier)
            return environment.stringLanguage
        }
        #expect(language("zh-Hant") == "zh-Hant")
        #expect(language("zh_TW") == "zh-Hant-TW")
        #expect(language("pt_BR") == "pt-BR")
        #expect(language("de") == "de")
        #expect(language("de_CH") == "de-CH")
        var root = EnvironmentValues()
        root.publishUserLocale(Locale(identifier: "zh_TW"))
        #expect(root.stringLanguage == nil, "the root's locale names no language of a subtree's own")
    }

    @MainActor
    @Test("A key under a subtree's Traditional locale reads the Traditional table, from a bundle or registered")
    func subtreeReadsTheScript() throws {
        let files = try TableBundle([
            "en": ["Localizable": ["greeting": "Hello"]],
            "zh-Hans": ["Localizable": ["greeting": "你好-简"]],
            "zh-Hant": ["Localizable": ["greeting": "你好-繁"]],
        ])
        func drawn(_ view: some View) -> String {
            renderToBuffer(view, context: makeBareRenderContext(width: 20, height: 1)).lines.map(\.stripped).joined()
        }
        func greeting(_ identifier: String) -> String {
            drawn(Text("greeting", bundle: files.bundle).environment(\.locale, Locale(identifier: identifier)))
        }
        #expect(greeting("zh-Hant").hasPrefix("你好-繁"), "\(greeting("zh-Hant"))")
        #expect(greeting("zh_TW").hasPrefix("你好-繁"), "\(greeting("zh_TW"))")
        #expect(greeting("zh-Hans").hasPrefix("你好-简"), "\(greeting("zh-Hans"))")
        #expect(greeting("zh").hasPrefix("你好-简"), "\(greeting("zh"))")

        LocalizationService.shared.registerWithoutRendering(translations: [
            "en": ["test.h54.subtree": "Settings"], "zh": ["test.h54.subtree": "设置"],
            "zh-Hant": ["test.h54.subtree": "設定"],
        ])
        let traditional = drawn(Text("test.h54.subtree").environment(\.locale, Locale(identifier: "zh_HK")))
        #expect(traditional.hasPrefix("設定"), "\(traditional)")
        let words = drawn(Text("button.cancel").environment(\.locale, Locale(identifier: "zh-Hant")))
        #expect(words.hasPrefix("Cancel"), "TUI's Simplified words under a Traditional locale: \(words)")
    }

    // MARK: - Folders off Darwin

    @Test("Off Darwin a code finds the folder of its language and script, however spelt")
    func portableFolders() {
        let match = BundleStringTables.localization(for:among:)
        #expect(match("zh-Hant", ["en", "zh-Hans", "zh-Hant"]) == "zh-Hant")
        #expect(match("zh-Hant", ["en", "zh_CN", "zh_TW"]) == "zh_TW")
        #expect(match("zh-Hant", ["en", "zh", "zh-Hans"]) == nil, "Simplified is no Traditional")
        #expect(match("zh", ["en", "zh_TW", "zh-Hans"]) == "zh-Hans")
        #expect(match("de", ["en", "de_CH", "de"]) == "de", "the folder with no region first")
        #expect(match("de", ["en", "de_CH"]) == "de_CH")
        #expect(match("ja", ["en", "de"]) == nil)
    }
}
