//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentVariableCoverageTests.swift
//
//  What stops the list rotting: a variable read anywhere in the sources has to be in
//  the public table or the internal list, and an entry in either has to be read.
//
//  A test rather than a script run beside the build because it reads the table
//  itself, not a parse of its source, and it runs wherever `swift test` does, the
//  Linux lanes included, where a script run by the macOS validators would not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIEnvironmentDocs

@Suite("Every environment variable is documented")
struct EnvironmentVariableCoverageTests {
    private static let table = Set(TUIEnvironmentVariables.all.map(\.name))

    /// What each directory may hold besides the package's Swift: the tools are Python
    /// and shell, CI is YAML, and the articles mention variables by name too.
    private static let sourceExtensions: Set<String> = ["swift", "md"]
    private static let toolExtensions: Set<String> = ["swift", "py", "sh", "ps1", "yml", "md"]

    /// Every `TUI_` name in the package's own sources and manifest.
    private static func tuiNamesInSources() -> Set<String> {
        var names = SourceTree.tuiNames(in: SourceTree.bytes(of: SourceTree.root.appendingPathComponent("Package.swift")))
        for file in SourceTree.files(under: "Sources", extensions: sourceExtensions) {
            names.formUnion(SourceTree.tuiNames(in: SourceTree.bytes(of: file)))
        }
        return names
    }

    /// Every other name in capitals that a Swift file in the sources holds as a string,
    /// if it's a file that reads the environment.
    private static func literalsInReadingFiles() -> Set<String> {
        var names: Set<String> = []
        for file in SourceTree.files(under: "Sources", extensions: ["swift"]) {
            let bytes = SourceTree.bytes(of: file)
            if SourceTree.readsEnvironment(bytes) { names.formUnion(SourceTree.capitalLiterals(in: bytes)) }
        }
        return names
    }

    /// What the other tests here rest on: a scan that found nothing would pass them all.
    @Test("The scan finds a read in each shape the package writes one, and nothing it shouldn't")
    func scanFindsReads() {
        func literals(_ source: String) -> Set<String> { SourceTree.capitalLiterals(in: Array(source.utf8)) }
        func names(_ source: String) -> Set<String> { SourceTree.tuiNames(in: Array(source.utf8)) }
        func reads(_ source: String) -> Bool { SourceTree.readsEnvironment(Array(source.utf8)) }

        #expect(literals(#"environment["NEW_VAR"] == "1""#) == ["NEW_VAR"])
        #expect(literals(#"["SSH_TTY", "OTHER"].contains { environment[$0] != nil }"#) == ["SSH_TTY", "OTHER"])
        #expect(literals(#"(.reduceMotion, "TUI_X", "reduceMotion")"#) == ["TUI_X"])
        #expect(literals(#"let lower = "lower"; let mixed = "Mixed_CASE""#).isEmpty)

        #expect(names("`TUI_X=1` and TUI_Y.") == ["TUI_X", "TUI_Y"])
        #expect(names("SWIFTUI_MODULES, TUI_TUIStrings and TUI_ alone").isEmpty)

        for read in [
            #"getenv("X")"#, "ProcessInfo.processInfo.environment", #"environment["X"]"#, #"env["X"]"#,
            "func f(environment: [String: String])", #"Context.environment["X"]"#,
        ] {
            #expect(reads(read), "\(read)")
        }
        #expect(!reads(#"let table: [String: String] = ["A": "B"]"#))
    }

    @Test("A variable read in the sources is in the table or the internal list")
    func everyReadIsListed() {
        let known = Self.table.union(InternalVariables.all).union(InternalVariables.compileConditions)
            .union(InternalVariables.notVariables)
        let unlisted = Self.tuiNamesInSources().union(Self.literalsInReadingFiles()).subtracting(known)
        #expect(
            unlisted.isEmpty,
            """
            Sources read \(unlisted.sorted()), which aren't documented. A variable someone would set \
            belongs in TUIEnvironmentVariables' table; one for debugging TUI itself goes in \
            Tests/TUIEnvironmentDocsTests/InternalVariables.swift and in \
            Documentation/Environment variables for developing TUI.md. A string in capitals \
            that isn't a variable goes in InternalVariables.notVariables.
            """)
    }

    @Test("A name in the tests or the tools is known too, so none of them drifts into being public")
    func everyToolNameIsListed() {
        var names: Set<String> = []
        for directory in ["Tests", "Tools", "Benchmarks", "scripts", ".github"] {
            for file in SourceTree.files(under: directory, extensions: Self.toolExtensions) {
                names.formUnion(SourceTree.tuiNames(in: SourceTree.bytes(of: file)))
            }
        }
        let known = Self.table.union(InternalVariables.all).union(InternalVariables.compileConditions)
        let unlisted = names.subtracting(known)
        #expect(unlisted.isEmpty, "\(unlisted.sorted()) belong in InternalVariables.testsAndTools.")
    }

    @Test("Every entry is still read, so nothing is documented that does nothing")
    func nothingIsStale() {
        let read = Self.tuiNamesInSources().union(Self.literalsInReadingFiles())
        let stale = Self.table.subtracting(read)
        #expect(stale.isEmpty, "\(stale.sorted()) are in the table, and nothing in the sources reads them.")
        // The internal names are checked against their own places.
        let staleInternal = InternalVariables.framework.union(InternalVariables.exampleAndStress).subtracting(read)
        #expect(staleInternal.isEmpty, "\(staleInternal.sorted()) are listed, and nothing in the sources reads them.")
    }

    @Test("No name is both public and internal, and tests-only names stay out of the end users' list")
    func audiencesAreKeptApart() {
        #expect(Self.table.isDisjoint(with: InternalVariables.all))
        #expect(Self.table.isDisjoint(with: InternalVariables.compileConditions))
        #expect(InternalVariables.framework.isDisjoint(with: InternalVariables.exampleAndStress))
        #expect(InternalVariables.framework.isDisjoint(with: InternalVariables.testsAndTools))
        #expect(InternalVariables.exampleAndStress.isDisjoint(with: InternalVariables.testsAndTools))
    }

    @Test("The inward-facing page names exactly the internal list")
    func internalPageMatches() throws {
        let page = try SourceTree.text(of: "Documentation/Environment variables for developing TUI.md")
        let named = SourceTree.tuiNames(in: Array(page.utf8))
        #expect(InternalVariables.all.subtracting(named).isEmpty, "The page doesn't say what these are for.")
        #expect(
            named.subtracting(InternalVariables.all).subtracting(Self.table)
                .subtracting(InternalVariables.compileConditions).isEmpty,
            "The page names something that isn't a variable any more.")
    }
}
