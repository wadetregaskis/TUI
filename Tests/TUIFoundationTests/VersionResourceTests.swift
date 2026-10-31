//  🖥️ TUI — A Terminal UI framework for Swift
//  VersionResourceTests.swift
//
//  `tuiVersion` reads a bundled resource and falls back to the string
//  "unknown" when it cannot. That fallback is silent by design, and resource
//  bundling is a BUILD-configuration fact, not a code one — it depends on the
//  `resources:` declaration in `Package.swift` surviving every target edit.
//  Drop `.copy("VERSION")` and the package still builds, every other test still
//  passes, and every consumer's `--version` flag, crash-report header and
//  bug-report template says "unknown" until a user files a report with no
//  version in it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@Suite("Bundled VERSION resource")
struct VersionResourceTests {

    /// The file the resource is copied from. NOT the package root — it lives
    /// beside the module's sources, which is what `Package.swift` names.
    private static let versionFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TUIFoundationTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/TUIStrings/VERSION")

    @Test("The resource resolves, so the version is not the silent fallback")
    func resourceResolves() {
        #expect(
            tuiVersion != "unknown",
            "No TUI resource bundle with VERSION was found (ModuleResources) — check `resources:` in Package.swift")
    }

    @Test("The version is a semantic version, trimmed")
    func versionShape() {
        #expect(
            tuiVersion.wholeMatch(of: /\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?/) != nil,
            "not a semantic version: \(tuiVersion.debugDescription)")
        // Pins the `trimmingCharacters` call: the file on disk ends in a
        // newline, and an untrimmed version string would be pasted straight
        // into a `--version` line.
        #expect(tuiVersion == tuiVersion.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("The bundled copy is the file in the source tree")
    func matchesTheSourceFile() throws {
        let onDisk = try String(contentsOf: Self.versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(tuiVersion == onDisk)
    }

    @Test("A program without the bundle reads the version as unknown")
    func noBundleReadsUnknown() {
        #expect(readTUIVersion(from: .absent) == "unknown")
    }

    @Test("The version is read from whichever bundle is found, trimmed")
    func readsTheFoundBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-version-\(UUID().uuidString)", isDirectory: true)
        let bundle = directory.appendingPathComponent("TUI_TUIStrings.resources", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(" 9.8.7\n".utf8).write(to: bundle.appendingPathComponent("VERSION"))
        #expect(readTUIVersion(from: ModuleResources(searching: [directory])) == "9.8.7")
    }
}
