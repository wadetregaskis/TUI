//  🖥️ TUI — A Terminal UI framework for Swift
//  LanguageScriptAndRegionTests.swift
//
//  A language is told apart by its script: TUI's Chinese is Simplified, so a
//  reader of Traditional Chinese (`zh_TW`, `zh-Hant`) is not given it, and
//  reads the app's own Traditional strings and then the next language they
//  name (hunt TOOLS-10).
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
                == ["zh-Hant", "ja"])
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
        #expect(service.lookupLanguageCodes == ["zh-Hant", "en"])
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
