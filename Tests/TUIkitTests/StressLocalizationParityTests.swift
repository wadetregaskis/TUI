//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressLocalizationParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The Stress harness's tables, read from source like the Example's.
///
/// The catalogue is the extra check here: a scenario's menu row is built from
/// `stress.scenario.<id>.title/blurb/stresses`, and `L` returns the KEY when a
/// table lacks it — so a scenario added without its strings showed its key in
/// the menu, in every language, and nothing failed.
@Suite("Stress localization parity")
struct StressLocalizationParityTests {
    private static func loadTables() -> (tables: [String: [String: String]], filesRead: Int) {
        LocalizationSourceTables.load(under: ["Sources/Stress/Localization"])
    }

    /// Every scenario the registry lists, with its id as the source spells it.
    ///
    /// The registry is `Scenarios.all`'s `Foo.descriptor,` entries in
    /// Scenario.swift. Each id is the `id:` argument that opens its type's
    /// `static let descriptor = Scenario(`: a string literal, or the name of a
    /// `static let` string the type declares. An id this cannot read comes
    /// back `nil`, and the test fails on it. An earlier scan took every line
    /// shaped `id: "…",` anywhere in the folder, so it silently skipped the
    /// descriptors that say `id: scenarioID,` (table-api, app-shapes and
    /// controls were never checked) and read a variant's `id:` as a scenario's.
    private static func registeredScenarios() -> [(type: String, id: String?)] {
        let stress = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Stress")
        let registryPath = (stress as NSString).appendingPathComponent("Scenario.swift")
        guard let registry = try? String(contentsOfFile: registryPath, encoding: .utf8),
              let list = registry.range(of: "static let all: [Scenario] = [")
        else { return [] }
        let listEnd = registry.range(of: "]", range: list.upperBound..<registry.endIndex)?.lowerBound
            ?? registry.endIndex
        let types = registry[list.upperBound..<listEnd].split(separator: "\n").compactMap { line -> String? in
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard entry.hasSuffix(".descriptor,") else { return nil }
            return String(entry.dropLast(".descriptor,".count))
        }
        var sources: [String] = []
        let files = FileManager.default.enumerator(atPath: stress)?.compactMap { $0 as? String } ?? []
        for name in files.sorted() where name.hasSuffix(".swift") {
            let path = (stress as NSString).appendingPathComponent(name)
            if let source = try? String(contentsOfFile: path, encoding: .utf8) { sources.append(source) }
        }
        return types.map { type in (type, sources.lazy.compactMap { descriptorID(of: type, in: $0) }.first) }
    }

    /// The id `type`'s descriptor declares in `source`, or `nil` when `source`
    /// does not declare the type or its descriptor's first argument is not a
    /// readable `id:`.
    private static func descriptorID(of type: String, in source: String) -> String? {
        let declaration = ["enum \(type) ", "enum \(type):", "struct \(type) ", "struct \(type):"]
            .compactMap { source.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let declaration,
              let descriptor = source.range(
                  of: "static let descriptor = Scenario(", range: declaration.upperBound..<source.endIndex)
        else { return nil }
        let arguments = source[descriptor.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        guard let first = arguments.first, first.hasPrefix("id:") else { return nil }
        let argument = first.dropFirst("id:".count).drop { $0 == " " }
        if argument.first == "\"" {
            return String(argument.dropFirst().prefix { $0 != "\"" })
        }
        let name = argument.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !name.isEmpty,
              let constant = source.range(
                  of: "static let \(name) = \"", range: declaration.upperBound..<source.endIndex)
        else { return nil }
        return String(source[constant.upperBound...].prefix { $0 != "\"" })
    }

    @Test("Every Stress language has exactly the English key set")
    func everyLanguageMatchesEnglish() {
        let (tables, filesRead) = Self.loadTables()
        #expect(filesRead > 0, "no Stress string tables were read")
        guard let english = tables["en"] else {
            Issue.record("no English table found")
            return
        }
        #expect(english.count > 50, "the English table looks truncated")
        #expect(tables.count == 7, "expected en + 6 translations")

        let englishKeys = Set(english.keys)
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let keys = Set(table.keys)
            let missing = englishKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(englishKeys).sorted()
            #expect(missing.isEmpty, "\(language) is missing \(missing.count) keys: \(missing.prefix(5))")
            #expect(extra.isEmpty, "\(language) has \(extra.count) keys English does not: \(extra.prefix(5))")
        }
    }

    @Test("Every scenario has its title, blurb and stresses in every language")
    func everyScenarioIsDescribed() {
        let (tables, _) = Self.loadTables()
        let scenarios = Self.registeredScenarios()
        // Hoisted: no closure literal inside `#expect` (see Tools/CompilerBugs'
        // MacroClosureDiscriminatorCollision).
        let types = scenarios.map { $0.type }
        #expect(types.count >= 20, "the registry looks truncated: \(types)")
        for scenario in scenarios where scenario.id == nil {
            Issue.record(
                """
                could not read \(scenario.type)'s id: its descriptor must open with `id:` and a string \
                literal, or the name of a `static let` string the type declares
                """)
        }
        let ids = scenarios.compactMap { $0.id }
        #expect(Set(ids).count == ids.count, "two scenarios share an id: \(ids.sorted())")
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) {
            for id in ids {
                for field in ["title", "blurb", "stresses"] {
                    let key = "stress.scenario.\(id).\(field)"
                    #expect(table[key] != nil, "\(language) lacks \(key)")
                }
            }
        }
    }

    @Test("No Stress translation was left as its English text")
    func translationsAreNotCopies() {
        let (tables, _) = Self.loadTables()
        guard let english = tables["en"] else { return }
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let shared = Set(table.keys).intersection(english.keys)
            let identical = shared.count { table[$0] == english[$0] }
            let ratio = Double(identical) / Double(max(1, shared.count))
            #expect(ratio < 0.5, "\(language): \(identical)/\(shared.count) strings are byte-identical to English")
        }
    }
}
