//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableCompactTests.swift
//
//  A table in a horizontally compact size class shows its first column alone
//  and no headers (decisions B3). SwiftUI's side is its own documentation,
//  macOS never being compact: "on iPhone or in a compact horizontal size class
//  environment … the table automatically hides headers and all columns after
//  the first".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A table in a compact size class shows its first column alone")
struct TableCompactTests {
    private struct Planet: Identifiable, Sendable {
        let id: Int
        let name: String
        let moons: String
    }

    private static let planets = [
        Planet(id: 0, name: "Mars, the red one", moons: "Phobos"),
        Planet(id: 1, name: "Earth", moons: "Luna"),
    ]

    private func lines(_ sizeClass: UserInterfaceSizeClass, width: Int = 40) -> [String] {
        renderToBuffer(
            Table(Self.planets) {
                TableColumn("Name", value: \Planet.name).width(8)
                TableColumn("Moons", value: \Planet.moons)
            }
            .environment(\.horizontalSizeClass, sizeClass),
            context: makeRenderContext(width: width, height: 6)
        ).lines.map(\.stripped)
    }

    @Test("Regular: the header, and every column at its width")
    func regular() {
        let drawn = lines(.regular)
        #expect(drawn.contains { $0.contains("Name") && $0.contains("Moons") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("Earth") && $0.contains("Luna") }, "\(drawn)")
        #expect(!drawn.contains { $0.contains("Mars, the red one") }, "the 8-cell column was not cut: \(drawn)")
    }

    @Test("Compact: no header, the first column alone, across the table's width")
    func compact() {
        let drawn = lines(.compact)
        #expect(!drawn.contains { $0.contains("Name") || $0.contains("Moons") }, "\(drawn)")
        #expect(!drawn.contains { $0.contains("Phobos") || $0.contains("Luna") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("Mars, the red one") }, "\(drawn)")
        // The first row takes the line the header had: right under the border.
        #expect(drawn.count > 1 && drawn[1].contains("Mars"), "\(drawn)")
    }
}
