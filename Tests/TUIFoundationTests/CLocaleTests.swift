//  🖥️ TUI — A Terminal UI framework for Swift
//  CLocaleTests.swift
//
//  `LC_ALL=C` and `LC_MESSAGES=C` (and `POSIX`) mean English, on Linux and
//  macOS alike: the owner's O-07 (b), 2026-11-21 (hunt XPLAT-4, TOOLS-11).
//  They meant "no preference", so the next variable spoke and `LC_ALL=C` on
//  a German machine was German.
//
//  Posed through the injected environment and preferred-languages list, so
//  both platforms' inputs run on either and nothing reads, or writes, the
//  process's own: the macOS path has a genuine preferred list (`de-DE`), the
//  Linux one Foundation's sentinel (`en-001`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings

@Suite("The C locale means English")
struct CLocaleTests {
    private func detected(_ environment: [String: String], _ preferred: [String]) -> LocalizationService.Language? {
        LocalizationService.systemPreferredLanguage(environment: environment, preferredLanguages: preferred)
    }

    @Test("LC_ALL=C gives English over a German LANG and LANGUAGE, on the macOS path and the Linux one")
    func cMeansEnglish() {
        let german = ["LANG": "de_DE.UTF-8", "LANGUAGE": "de"]
        for neutral in ["C", "POSIX", "C.UTF-8", "C.utf8"] {
            let environment = german.merging(["LC_ALL": neutral]) { $1 }
            #expect(detected(environment, ["de-DE"]) == .english, "\(neutral), macOS")
            #expect(detected(environment, ["en-001"]) == .english, "\(neutral), Linux")
            #expect(
                LocalizationService.systemPreferredLanguageCodes(environment: environment, preferredLanguages: ["de-DE"])
                    == ["en"])
        }
        #expect(detected(["LC_MESSAGES": "C", "LANG": "de_DE.UTF-8"], ["de-DE"]) == .english)
        #expect(detected(["LANG": "C", "LANGUAGE": "de"], ["de-DE"]) == .english, "gettext ignores LANGUAGE under C")
    }

    @Test("Only the variable that decides counts: a C below a language is not read")
    func onlyTheDecidingVariable() {
        #expect(detected(["LC_ALL": "de_DE.UTF-8", "LANG": "C"], []) == .german)
        #expect(detected(["LC_MESSAGES": "fr_FR", "LANG": "C"], []) == .french)
        #expect(detected(["LC_ALL": "", "LANG": "C"], ["de-DE"]) == .english, "an empty variable is unset")
        #expect(detected(["LC_CTYPE": "C", "LANG": "de_DE"], []) == .german, "LC_CTYPE says nothing of messages")
        #expect(detected([:], ["de-DE"]) == .german, "no variable at all still reads the system's languages")
    }

    @Test("A service started under LC_ALL=C is English with no region")
    func service() {
        let directory = NSTemporaryDirectory() + "tuikit-h54-c-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let service = LocalizationService(
            configDirectoryPath: directory, environment: ["LC_ALL": "C", "LANG": "de_DE.UTF-8", "LANGUAGE": "de"])
        #expect(service.currentLanguage == .english)
        #expect(service.lookupLanguageCodes == ["en"])
        #expect(service.currentLocale.region == nil)
        #expect(service.frameworkString(for: "button.cancel") == "Cancel")
    }

    @Test("A C among the variables that decide the region gives no region, not the system's")
    func noRegion() {
        let region = LocalizationService.systemRegion
        let current = Locale(identifier: "en_NZ")
        #expect(region(["LC_ALL": "C", "LANG": "de_DE.UTF-8"], current) == nil)
        #expect(region(["LANG": "C"], current) == nil)
        #expect(region(["LC_TIME": "POSIX", "LANG": "de_DE"], current) == nil)
        #expect(region(["LC_ALL": "de_AT", "LANG": "C"], current)?.identifier == "AT")
    }
}
