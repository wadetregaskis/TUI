//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameTraceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIView

@MainActor
@Suite("TUI_FRAME_TRACE")
struct FrameTraceTests {
    /// The lines written to a trace after `body` has used it, without the header.
    private func lines(_ body: (FrameTrace) throws -> Void) throws -> [[String]] {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-trace-\(UUID().uuidString).tsv").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let trace = try #require(FrameTrace(destination: path))
        try body(trace)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return text.split(separator: "\n").dropFirst().map { $0.split(separator: "\t").map(String.init) }
    }

    @Test("Unset, or a file that can't be made, is no trace at all")
    func noTrace() {
        #expect(FrameTrace(destination: nil) == nil)
        #expect(FrameTrace(destination: "") == nil)
        #expect(FrameTrace(destination: "/nonexistent-directory/frames.tsv") == nil)
    }

    @Test("A line gives the frame's number, its own bytes and every cause since the last")
    func aLine() throws {
        let cache = RenderCache()
        let written = try lines { trace in
            trace.record(startNanos: 0, totalBytes: 100, cache: cache)
            trace.note(.input)
            trace.note(.state)
            trace.record(startNanos: 0, totalBytes: 130, cache: cache)
            trace.record(startNanos: 0, totalBytes: 130, cache: cache)
        }
        #expect(written.map { $0[0] } == ["1", "2", "3"])
        #expect(written.map { $0[3] } == ["100", "30", "0"])
        #expect(written.map { $0[6] } == ["launch", "input+state", "other"])
    }

    @Test("A replay is a line if it wrote anything, and leaves the next frame's causes alone")
    func aReplay() throws {
        let cache = RenderCache()
        let written = try lines { trace in
            trace.note(.state)
            trace.recordReplay(startNanos: 0, totalBytes: 0, cache: cache)
            trace.recordReplay(startNanos: 0, totalBytes: 68, cache: cache)
            trace.record(startNanos: 0, totalBytes: 100, cache: cache)
        }
        #expect(written.map { $0[6] } == ["replay", "launch+state"])
        #expect(written.map { $0[3] } == ["68", "32"])
    }
}
