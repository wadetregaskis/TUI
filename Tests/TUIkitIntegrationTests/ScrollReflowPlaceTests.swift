//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollReflowPlaceTests.swift
//
//  A page drawn whole — a `VStack` in a `ScrollView`, as most pages are —
//  keeps roughly the same part of itself in view when the window's width
//  changes and its text rewraps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Forty sections of text long enough to wrap onto two lines at 60 columns
/// and three at 40.
private struct ReflowingPage: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        Text(
                            "Section \(index): " + String(repeating: "word ", count: 18))
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("A page reflowed by its width")
struct ScrollReflowPlaceTests {
    private static let frameNanos: Int64 = 16_666_667

    /// The section at the top of the screen, by its number.
    private func topSection(_ app: HeadlessApp<ReflowingPage>) -> Int? {
        for line in app.screen {
            guard let range = line.range(of: "Section ") else { continue }
            let digits = line[range.upperBound...].prefix { $0.isNumber }
            if let number = Int(digits) { return number }
        }
        return nil
    }

    @Test("Narrowed, it keeps the section it showed at the top, near enough")
    func narrowingKeepsThePlace() throws {
        let app = HeadlessApp(ReflowingPage(), width: 60, height: 20)
        var now: Int64 = 0
        app.frame(atNanos: now)
        for _ in 0..<8 {
            _ = app.send(MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 5))
            now += Self.frameNanos
            app.frame(atNanos: now)
        }
        let before = try #require(topSection(app), "\(app.screen)")
        #expect(before > 4, "precondition: scrolled into the page: \(app.screen)")
        app.resize(width: 40, height: 20)
        for _ in 0..<2 {
            now += Self.frameNanos
            app.frame(atNanos: now)
        }
        let after = try #require(topSection(app), "\(app.screen)")
        #expect(abs(after - before) <= 1, "section \(before) was at the top; now \(after) is: \(app.screen)")
    }
}
