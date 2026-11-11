//  🖥️ TUI — A Terminal UI framework for Swift
//  AllProgramsSettingsFileTests.swift
//
//  The person's file of settings for all programs, `defaults.json` (the
//  owner's USET-PLACE, 2026-11-10): hand-editable JSON, an entry that doesn't
//  make sense skipped on its own, unknown keys kept on rewrite, a file that
//  isn't a JSON object never written over, and two programs sharing it. Every
//  file is a temporary one: nothing here reads or writes a real home.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIFoundation

@MainActor
@Suite("The settings for all programs, in their file", .serialized)
struct AllProgramsSettingsFileTests {
    /// A file in a folder of its own, which does not exist yet.
    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tui-all-programs-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("TUI", isDirectory: true)
            .appendingPathComponent("defaults.json")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func object(at url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test("No file sets nothing, and the first change makes the file and its folder")
    func noFile() throws {
        let url = scratchFile()
        let file = AllProgramsSettingsFile(url: url)
        #expect(file.read() == SettingsLayer())
        #expect(file.write(.bool(true), for: .preference(.reduceMotion)))
        let written = try object(at: url)
        #expect(written["reduceMotion"] as? Bool == true)
        #expect(file.read().isOn(.reduceMotion) == true)
    }

    @Test("An entry that doesn't make sense is skipped on its own, never the file")
    func partialFile() throws {
        let url = scratchFile()
        try write(
            """
            {
              "reduceMotion": true,
              "borderStyle": "heavy",
              "palette": "no-such-palette",
              "increaseContrast": 1,
              "spelledOutKeys": "yes",
              "controlStyle": true,
              "aSettingFromALaterTUI": [1, 2]
            }
            """, to: url)
        let layer = AllProgramsSettingsFile(url: url).read()
        #expect(layer.isOn(.reduceMotion) == true)
        #expect(layer.identifier(.borderStyle) == "heavy")
        #expect(layer.identifier(.palette) == nil, "a palette TUI doesn't have")
        #expect(layer.isOn(.increaseContrast) == nil, "a number is not a check's value")
        #expect(layer.isOn(.spelledOutKeys) == nil)
        #expect(layer.identifier(.controlStyle) == nil)
        #expect(layer.values.count == 2)
    }

    @Test("A write changes its own key and keeps every other, those TUI doesn't know included")
    func unknownKeysKept() throws {
        let url = scratchFile()
        try write(#"{"aSettingFromALaterTUI": {"nested": [1, "two", null]}, "palette": "no-such-palette", "reduceMotion": true}"#, to: url)
        let file = AllProgramsSettingsFile(url: url)
        #expect(file.write(.identifier("amber"), for: .display(.palette)))
        #expect(file.write(nil, for: .preference(.reduceMotion)))
        let written = try object(at: url)
        #expect(written["palette"] as? String == "amber")
        #expect(written["reduceMotion"] == nil, "given back: the key goes")
        let kept = try #require(written["aSettingFromALaterTUI"] as? [String: Any])
        let nested = try #require(kept["nested"] as? [Any])
        #expect(nested.count == 3 && nested[1] as? String == "two" && nested[2] is NSNull)
    }

    @Test("A file that isn't a JSON object is not read, and never written over")
    func corruptFile() throws {
        for text in ["{ \"reduceMotion\": tru", "[true]", ""] {
            let url = scratchFile()
            try write(text, to: url)
            let failures = StorageDiagnostics.failureCount
            let file = AllProgramsSettingsFile(url: url)
            #expect(file.read() == SettingsLayer(), "\(text)")
            #expect(!file.write(.bool(true), for: .preference(.reduceMotion)), "\(text)")
            #expect(try String(contentsOf: url, encoding: .utf8) == text, "the person's text is as they left it")
            #expect(StorageDiagnostics.failureCount > failures, "reported, as any store's failure is")
        }
    }

    @Test("Two programs share the file: each writes only what it changed, and reads the other's when it looks again")
    func twoPrograms() throws {
        let url = scratchFile()
        let first = ViewPreferenceOverrides()
        let second = ViewPreferenceOverrides()
        first.adopt(programStore: nil, allProgramsFile: AllProgramsSettingsFile(url: url))
        second.adopt(programStore: nil, allProgramsFile: AllProgramsSettingsFile(url: url))

        first.setForAllPrograms(.display(.palette), .identifier("amber"))
        second.setForAllPrograms(.preference(.reduceMotion), .bool(true))
        let written = try object(at: url)
        #expect(written["palette"] as? String == "amber", "the second program's write kept the first's")
        #expect(written["reduceMotion"] as? Bool == true)

        #expect(first.allPrograms.isOn(.reduceMotion) == nil, "not seen until the first looks again")
        first.reloadAllPrograms()
        #expect(first.allPrograms.isOn(.reduceMotion) == true)
        #expect(first.allPrograms.identifier(.palette) == "amber")
    }

    @Test("Hand-edited, the file is one plain JSON object, written with its keys in order")
    func readableFile() throws {
        let url = scratchFile()
        let file = AllProgramsSettingsFile(url: url)
        file.write(.bool(false), for: .preference(.focusBreathing))
        file.write(.identifier("rounded"), for: .display(.borderStyle))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#""borderStyle" : "rounded""#), "\(text)")
        let border = try #require(text.range(of: "borderStyle"))
        let breathing = try #require(text.range(of: "focusBreathing"))
        #expect(border.lowerBound < breathing.lowerBound)
    }
}
