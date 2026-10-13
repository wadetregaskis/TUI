//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppLocaleRegionTests.swift
//
//  `\.locale` is the app's language with the user's region (deviation E3,
//  closed by the owner's ruling of 2026-10-13): a German app run under
//  `LANG=en_GB.UTF-8` formats as German written for Britain, where it used to
//  be a bare `de` with no region at all. The region is read the way the
//  language is, the POSIX variables first.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

@Suite("The app's locale carries the user's region")
struct AppLocaleRegionTests {

    // MARK: - A language in a region

    @Test("A language in a region is that language, written for that region")
    func languageInARegion() {
        let locale = LocalizationService.Language.german.locale(in: Locale.Region("GB"))
        #expect(locale.language.languageCode?.identifier == "de")
        #expect(locale.region?.identifier == "GB")
    }

    @Test("With no region a language is its bare code, as before")
    func noRegion() {
        #expect(LocalizationService.Language.english.locale(in: nil).identifier == "en")
        #expect(LocalizationService.Language.french.locale(in: nil).region == nil)
    }

    @Test("Simplified Chinese stays simplified in a region whose own Chinese is traditional")
    func simplifiedChineseKeepsItsScript() {
        let locale = LocalizationService.Language.simplifiedChinese.locale(in: Locale.Region("TW"))
        #expect(locale.language.languageCode?.identifier == "zh")
        #expect(locale.language.script == .hanSimplified)
        #expect(locale.region?.identifier == "TW")
    }

    // MARK: - Where the region comes from

    @Test("The POSIX variables name the region, in the precedence that decides how dates and numbers are written")
    func posixPrecedence() {
        let region = LocalizationService.systemRegion
        #expect(region(["LANG": "en_GB.UTF-8"], nil)?.identifier == "GB")
        #expect(region(["LANG": "en_GB.UTF-8", "LC_NUMERIC": "de_CH.UTF-8"], nil)?.identifier == "CH")
        #expect(region(["LC_NUMERIC": "de_CH", "LC_TIME": "fr_BE"], nil)?.identifier == "BE")
        #expect(region(["LC_TIME": "fr_BE", "LC_ALL": "de_AT.UTF-8@euro"], nil)?.identifier == "AT")
        #expect(region(["LANG": "zh-Hant-TW"], nil)?.identifier == "TW", "a script before the territory")
        #expect(region(["LANG": "es_419.UTF-8"], nil)?.identifier == "419", "a numeric region")
    }

    @Test("A variable naming no territory is skipped, and then the system's region is the user's")
    func fallsBackToTheSystem() {
        let region = LocalizationService.systemRegion
        let current = Locale(identifier: "en_NZ")
        #expect(region(["LANG": "C"], current)?.identifier == "NZ")
        #expect(region(["LC_ALL": "POSIX", "LANG": "de"], current)?.identifier == "NZ")
        #expect(region([:], current)?.identifier == "NZ")
        #expect(region([:], nil) == nil)
    }

    @Test("The world region swift-foundation reports with nothing to read is no region")
    func worldIsNoRegion() {
        #expect(LocalizationService.systemRegion(environment: [:], current: Locale(identifier: "en_001")) == nil)
    }

    // MARK: - The service

    private let configDir = NSTemporaryDirectory() + "tuikit-e3-\(UUID().uuidString)"

    @Test("The service's locale is its language with the region, through a change of language")
    func serviceLocale() {
        let service = LocalizationService(configDirectoryPath: configDir, environment: ["LANG": "en_GB.UTF-8"])
        #expect(service.currentLocale.language.languageCode?.identifier == "en")
        #expect(service.currentLocale.region?.identifier == "GB")
        service.pinLanguageForTesting(.german)
        #expect(service.currentLocale.language.languageCode?.identifier == "de")
        #expect(service.currentLocale.region?.identifier == "GB")
    }

    @Test("A region changes how a date is written: Britain puts the day first")
    func regionChangesTheFormat() {
        let date = Date(timeIntervalSince1970: 1_791_849_600)  // 2026-10-13, UTC
        let style = Date.FormatStyle(date: .numeric, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)
        let british = date.formatted(style.locale(LocalizationService.Language.english.locale(in: Locale.Region("GB"))))
        let bare = date.formatted(style.locale(LocalizationService.Language.english.locale(in: nil)))
        #expect(british.hasPrefix("13/"), "got \(british)")
        #expect(bare.hasPrefix("10/"), "got \(bare)")
    }

    @MainActor
    @Test("The environment's locale is the shared service's")
    func environmentPublishesIt() {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: TUIContext())
        #expect(environment.locale == LocalizationService.shared.currentLocale)
    }
}
