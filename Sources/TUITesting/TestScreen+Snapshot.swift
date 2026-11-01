//  🖥️ TUI — A Terminal UI framework for Swift
//  TestScreen+Snapshot.swift
//
//  Comparing a screen with a copy kept in a file beside the test.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension TestScreen {
    /// Compares the screen's text with a snapshot kept beside the test, in
    /// `__Snapshots__/<name>.txt` in the directory of the test's source file.
    ///
    /// A snapshot holds ``text``: wording and layout, not colour, so it reads as
    /// a picture of the screen, and its changes read well in a diff. The first
    /// run has none to compare with, so it writes one and throws, for you to
    /// look at it. To accept a change, run the tests with `TUI_RECORD_SNAPSHOTS=1`
    /// in the environment, which writes every snapshot instead of comparing.
    ///
    /// - Parameters:
    ///   - name: The snapshot's name, unique among the snapshots of that directory.
    ///   - filePath: The test's source file, which says where the directory is.
    /// - Throws: ``TestAppError`` if the screen differs, showing the rows that
    ///   do, or if there was no snapshot.
    public func compareToSnapshot(_ name: String, filePath: String = #filePath) throws {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
        let file = directory.appendingPathComponent("\(name).txt")
        let isRecording = ProcessInfo.processInfo.environment["TUI_RECORD_SNAPSHOTS"] != nil
        let stored = isRecording ? nil : try? String(contentsOf: file, encoding: .utf8)
        guard let stored else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            if isRecording { return }
            throw TestAppError("No snapshot “\(name)”, so it was written to \(file.path). Check it and run the test again.")
        }
        guard stored != text else { return }
        throw TestAppError("The screen differs from snapshot “\(name)”:\n\(Self.difference(from: stored, to: text))")
    }

    /// The rows that differ, `-` the snapshot's and `+` the screen's.
    private static func difference(from stored: String, to text: String) -> String {
        let old = stored.components(separatedBy: "\n")
        let new = text.components(separatedBy: "\n")
        return (0..<max(old.count, new.count)).compactMap { row -> String? in
            let was = row < old.count ? old[row] : nil
            let now = row < new.count ? new[row] : nil
            guard was != now else { return nil }
            return [was.map { "- \($0)" }, now.map { "+ \($0)" }].compactMap(\.self).joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
