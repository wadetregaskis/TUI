//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VersionResourceTests.swift
//
//  `tuiKitVersion` reads a bundled resource and falls back to the string
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

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

@Suite("Bundled VERSION resource")
struct VersionResourceTests {

    /// The file the resource is copied from. NOT the package root — it lives
    /// beside the module's sources, which is what `Package.swift` names.
    private static let versionFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TUIkitTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Sources/TUIkitStrings/VERSION")

    @Test("The resource resolves, so the version is not the silent fallback")
    func resourceResolves() {
        #expect(
            tuiKitVersion != "unknown",
            "Bundle.module could not read VERSION — check `resources:` in Package.swift")
    }

    @Test("The version is a semantic version, trimmed")
    func versionShape() {
        #expect(
            tuiKitVersion.wholeMatch(of: /\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?/) != nil,
            "not a semantic version: \(tuiKitVersion.debugDescription)")
        // Pins the `trimmingCharacters` call: the file on disk ends in a
        // newline, and an untrimmed version string would be pasted straight
        // into a `--version` line.
        #expect(tuiKitVersion == tuiKitVersion.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("The bundled copy is the file in the source tree")
    func matchesTheSourceFile() throws {
        let onDisk = try String(contentsOf: Self.versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(tuiKitVersion == onDisk)
    }

    @Test("A program without the bundle reads the version as unknown")
    func noBundleReadsUnknown() {
        #expect(readTUIkitVersion(from: .absent) == "unknown")
    }

    @Test("The version is read from whichever bundle is found, trimmed")
    func readsTheFoundBundle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-version-\(UUID().uuidString)", isDirectory: true)
        let bundle = directory.appendingPathComponent("TUIkit_TUIkitStrings.resources", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(" 9.8.7\n".utf8).write(to: bundle.appendingPathComponent("VERSION"))
        #expect(readTUIkitVersion(from: ModuleResources(searching: [directory])) == "9.8.7")
    }
}
