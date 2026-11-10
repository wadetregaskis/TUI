//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentVariableTableTests.swift
//
//  The table's own rules, the text it generates, and that TUI's published page is
//  that text and hasn't drifted from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIEnvironmentDocs

@Suite("The table of environment variables")
struct EnvironmentVariableTableTests {
    private static let pagePath = "Sources/TUI/TUI.docc/Articles/EnvironmentVariables.md"

    @Test("Names are unique, in capitals, and each entry says something")
    func entriesAreWellFormed() {
        var seen: Set<String> = []
        for variable in TUIEnvironmentVariables.all {
            #expect(seen.insert(variable.name).inserted, "\(variable.name) is in the table twice")
            let isCapitals = variable.name.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
            #expect(isCapitals, "\(variable.name)")
            #expect(!variable.values.isEmpty, "\(variable.name)")
            #expect(variable.effect.hasSuffix("."), "\(variable.name)'s effect is a sentence")
        }
    }

    /// A man page and a Markdown table each have characters that would break them.
    @Test("The text is ASCII, its code spans balance, and it doesn't break a table")
    func textIsPortable() {
        for variable in TUIEnvironmentVariables.all {
            for text in [variable.values, variable.effect, variable.codeSetting.explanation ?? ""] {
                let isASCII = text.allSatisfy(\.isASCII)
                #expect(isASCII, "\(variable.name): \(text)")
                #expect(!text.contains("|"), "\(variable.name): a | would end the table's cell")
                let spanMarks = text.filter { $0 == "`" }.count
                #expect(spanMarks.isMultiple(of: 2), "\(variable.name): \(text)")
                #expect(!text.contains("\n"), "\(variable.name)")
            }
        }
    }

    /// The person running an app reads what's in its man page: their own variables and
    /// what their terminal sets. Words about TUI's insides mean nothing to them.
    @Test("What an end user reads mentions no code and no framework jargon")
    func endUserTextIsForEndUsers() {
        let jargon = [
            "terminalclient", "render cache", "render memo", "memoiz", "`body`", "@scenestorage", "environment key",
            "environment value", "modifier", "renderable", "stderr", "view tree", "in the tree",
        ]
        let readers = TUIEnvironmentVariables.variables(for: .endUser) + TUIEnvironmentVariables.variables(for: .detected)
        for variable in readers {
            let text = (variable.values + " " + variable.effect).lowercased()
            for word in jargon {
                #expect(!text.contains(word), "\(variable.name) says \"\(word)\"")
            }
        }
        let introduction = TUIEnvironmentVariables.introduction(for: .endUser).lowercased()
        #expect(jargon.allSatisfy { !introduction.contains($0) })
    }

    @Test("Each topic belongs to one audience, so a man page's groups don't mix them")
    func topicsBelongToOneAudience() {
        var owner: [TUIEnvironmentVariable.Topic: TUIEnvironmentVariable.Audience] = [:]
        for variable in TUIEnvironmentVariables.all {
            let first = owner[variable.topic, default: variable.audience]
            #expect(first == variable.audience, "\(variable.name) is \(variable.audience) under \(variable.topic)")
            owner[variable.topic] = first
        }
        #expect(Set(owner.keys) == Set(TUIEnvironmentVariable.Topic.allCases), "A topic has no variables")
    }

    @Test("Each audience has what the page says it has")
    func audiences() {
        for audience in TUIEnvironmentVariable.Audience.allCases {
            #expect(!TUIEnvironmentVariables.variables(for: audience).isEmpty)
        }
        let developers = Set(TUIEnvironmentVariables.variables(for: .developer).map(\.name))
        #expect(developers.contains("TUI_RECORD_SNAPSHOTS"))
        let users = Set(TUIEnvironmentVariables.variables(for: .endUser).map(\.name))
        #expect(users.isSuperset(of: ["NO_COLOR", "FORCE_COLOR", "TUI_REDUCE_MOTION", "TERM"]))
        #expect(!users.contains("TUI_RECORD_SNAPSHOTS"))
    }

    /// The code a row names has to exist: a renamed setting would leave the page
    /// sending people to something that isn't there.
    @Test("A setting a row says code can make is in the sources")
    func namedSettingsExist() throws {
        var sources = ""
        for directory in ["Sources/TUIApp", "Sources/TUITerminalHost", "Sources/TUIStyling", "Sources/TUIView"] {
            for file in SourceTree.files(under: directory, extensions: ["swift"]) {
                sources += SourceTree.string(of: file)
            }
        }
        for variable in TUIEnvironmentVariables.all {
            let spans = (variable.codeSetting.explanation ?? "").split(separator: "`", omittingEmptySubsequences: false)
            for (index, span) in spans.enumerated() where !index.isMultiple(of: 2) {
                for owner in ["TerminalClient.", "ColorDepth.", "RenderCache."] where span.hasPrefix(owner) {
                    let member = span.dropFirst(owner.count).prefix { $0.isLetter }
                    #expect(sources.contains("var \(member)"), "\(variable.name) names \(span)")
                }
            }
        }
    }

    // MARK: - Man pages

    @Test("A man page section has its heading, its subsections and every variable", arguments: ManPageFormat.allCases)
    func manPageHasEverything(format: ManPageFormat) throws {
        let section = TUIEnvironmentVariables.manPageSection(format: format)
        let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == (format == .man ? ".SH ENVIRONMENT" : ".Sh ENVIRONMENT"))
        #expect(section.hasSuffix("\n"))
        let isASCII = section.allSatisfy(\.isASCII)
        #expect(isASCII)
        #expect(section.contains(format == .man ? ".SS Colour and appearance" : ".Ss Colour and appearance"))
        // The person's own variables, then what their terminal sets, after the last of theirs.
        for variable in TUIEnvironmentVariables.variables(for: .endUser) + TUIEnvironmentVariables.variables(for: .detected) {
            let entry = format == .man ? ".B \(variable.name)" : ".It Ev \(variable.name)"
            #expect(lines.contains(Substring(entry)), "\(variable.name)")
        }
        let subsection = format == .man ? ".SS" : ".Ss"
        let lastOwn = try #require(section.range(of: "\(subsection) Troubleshooting"))
        let terminalSets = try #require(section.range(of: "\(subsection) Set by your terminal"))
        #expect(lastOwn.lowerBound < terminalSets.lowerBound)
        for variable in TUIEnvironmentVariables.variables(for: .developer) {
            #expect(!section.contains(variable.name), "\(variable.name) is a developer's")
        }
    }

    @Test("No line of a man page is an accident: a request is one this writes, and a code span's hyphen stays one", arguments: ManPageFormat.allCases)
    func manPageLinesAreSafe(format: ManPageFormat) {
        let requests = format == .man ? [".SH", ".SS", ".TP", ".B"] : [".Sh", ".Ss", ".Bl", ".El", ".It", ".Li"]
        for line in TUIEnvironmentVariables.manPageSection(format: format).split(separator: "\n") {
            if line.hasPrefix(".") {
                #expect(requests.contains(String(line.prefix { $0 != " " })), "\(line)")
            }
            #expect(!line.hasPrefix("'"), "\(line)")
            #expect(!line.contains("`"), "\(line) kept a Markdown span")
        }
        // A code span's hyphen is one that has to survive being copied.
        let section = TUIEnvironmentVariables.manPageSection(format: format)
        #expect(section.contains("xterm\\-256color"))
        #expect(section.contains("Ctrl\\-Shift\\-Z"))
        #expect(section.contains("command-line"))
    }

    @Test("A man page section can leave its heading to the page around it", arguments: ManPageFormat.allCases)
    func manPageWithoutHeading(format: ManPageFormat) {
        let section = TUIEnvironmentVariables.manPageSection(format: format, includesHeading: false)
        #expect(!section.contains("ENVIRONMENT"))
        #expect(section.hasPrefix("This program"))
    }

    // MARK: - Markdown, and TUI's own page

    @Test("A Markdown section is a table per topic, the person's own and then what their terminal sets")
    func markdownSection() {
        let section = TUIEnvironmentVariables.markdownSection()
        #expect(section.hasPrefix("This program"))
        #expect(section.contains("### Colour and appearance\n\n| Variable | Values | Effect |\n|---|---|---|\n| `NO_COLOR` |"))
        #expect(section.contains("|\n\n### Set by your terminal\n\n| Variable | What it says |\n|---|---|\n| `TERM_PROGRAM` |"))
        #expect(TUIEnvironmentVariables.markdownSection(headingLevel: 2).contains("\n## Colour and appearance\n"))
        #expect(!TUIEnvironmentVariables.markdownSection(audience: .developer).contains("TERM_PROGRAM"))
    }

    /// The text between `<!-- tui-environment-docs: name -->` and the matching end in the page.
    private func generatedBlock(_ name: String, in page: String) throws -> String {
        let start = "<!-- tui-environment-docs: \(name) -->\n"
        let end = "<!-- /tui-environment-docs -->"
        let opening = try #require(page.range(of: start), "The page has no block \(name)")
        let closing = try #require(page.range(of: end, range: opening.upperBound..<page.endIndex))
        return String(page[opening.upperBound..<closing.lowerBound])
    }

    /// What holds the page to the table. The table in the page is what a person reads,
    /// and the table in code is what a man page gets, so they mustn't differ.
    @Test("The public page's tables are the generated ones", arguments: [
        ("end-user", TUIEnvironmentVariable.Audience.endUser),
        ("developer", .developer),
        ("detected", .detected),
    ])
    func pageHasTheAudience(name: String, audience: TUIEnvironmentVariable.Audience) throws {
        let page = try SourceTree.text(of: Self.pagePath)
        let expected = TUIEnvironmentVariables.markdownTables(audience: audience) + "\n"
        let actual = try generatedBlock(name, in: page).trimmedOfBlankEdges() + "\n"
        #expect(actual == expected.trimmedOfBlankEdges() + "\n", "Run `swift run tui-environment-docs --update-article`")
    }

    @Test("The public page's table of code settings is the generated one")
    func pageHasTheCodeSettings() throws {
        let page = try SourceTree.text(of: Self.pagePath)
        let expected = TUIEnvironmentVariables.markdownCodeSettings().trimmedOfBlankEdges()
        let actual = try generatedBlock("code", in: page).trimmedOfBlankEdges()
        #expect(actual == expected, "Run `swift run tui-environment-docs --update-article`")
    }
}

extension String {
    fileprivate func trimmedOfBlankEdges() -> String {
        trimmingCharacters(in: .newlines)
    }
}
