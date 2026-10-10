//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModuleResourcesTests.swift
//
//  TUIkit finds its resource bundle itself, and answers "none" where there is
//  none, rather than through SwiftPM's `Bundle.module`, which stops the program
//  there. Each test searches directories of its own, so none depends on where
//  this build put the bundle — except the last, which is about exactly that.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStrings

@Suite("Finding TUIkit's resource bundle")
struct ModuleResourcesTests {

    /// A fresh, empty directory of the test's own.
    private static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-module-resources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A bundle named `name` in `directory`, holding a `VERSION` of `version`.
    private static func makeBundle(_ name: String, in directory: URL, version: String) throws {
        let bundle = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(version.utf8).write(to: bundle.appendingPathComponent("VERSION"))
    }

    @Test("With no bundle in any place searched, there are no resources and no file URLs")
    func noBundleIsNone() throws {
        let empty = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        let resources = ModuleResources(searching: [nil, empty, empty.appendingPathComponent("missing")])
        #expect(resources.bundleURL == nil)
        #expect(resources.url(named: "VERSION", extension: nil) == nil)
        #expect(resources.url(named: "en", extension: "json", subdirectory: "translations") == nil)
    }

    @Test("A file with the bundle's name is not the bundle")
    func fileIsNotTheBundle() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ModuleResources.bundleNames {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        #expect(ModuleResources(searching: [directory]).bundleURL == nil)
    }

    @Test("The first place that holds the bundle is the one read, in either of SwiftPM's spellings")
    func firstPlaceWins() throws {
        let empty = try Self.scratchDirectory()
        let linux = try Self.scratchDirectory()
        let apple = try Self.scratchDirectory()
        defer { for url in [empty, linux, apple] { try? FileManager.default.removeItem(at: url) } }
        try Self.makeBundle("TUIkit_TUIkitStrings.resources", in: linux, version: "9.8.7\n")
        try Self.makeBundle("TUIkit_TUIkitStrings.bundle", in: apple, version: "1.2.3\n")

        let first = ModuleResources(searching: [empty, linux, apple])
        #expect(first.bundleURL?.lastPathComponent == "TUIkit_TUIkitStrings.resources")
        let version = try #require(first.url(named: "VERSION", extension: nil))
        #expect(try String(contentsOf: version, encoding: .utf8) == "9.8.7\n")

        let second = ModuleResources(searching: [apple, linux])
        #expect(second.bundleURL?.lastPathComponent == "TUIkit_TUIkitStrings.bundle")
    }

    @Test("The search starts beside the program")
    func searchStartsBesideTheProgram() {
        let directories = ModuleResources.searchDirectories()
        #expect(directories.first == Bundle.main.bundleURL)
        #expect(directories.count >= 3)
    }

    @Test("This build's own bundle is found where the build put it")
    func thisBuildsBundleIsFound() throws {
        let found = try #require(ModuleResources.current.bundleURL)
        #expect(ModuleResources.bundleNames.contains(found.lastPathComponent))
        #expect(ModuleResources.current.url(named: "en", extension: "json", subdirectory: "translations") != nil)
    }
}
