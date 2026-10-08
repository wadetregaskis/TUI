//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSubtitleTests.swift
//
//  `navigationSubtitle(_:)`: a pushed screen's subtitle follows its title on
//  the navigation bar's one row, and truncates first when the row is short.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Navigation subtitle", .rendersEnglishUI)
struct NavigationSubtitleTests {
    private struct Planet: Hashable {
        let name: String
    }

    private func bar(width: Int) -> [String] {
        var path = NavigationPath()
        path.append(Planet(name: "Mars"))
        let binding = Binding(get: { path }, set: { path = $0 })
        let view = NavigationStack(path: binding) {
            Text("root")
                .navigationTitle("Planets")
                .navigationDestination(for: Planet.self) { planet in
                    Text("surface")
                        .navigationTitle(planet.name)
                        .navigationSubtitle("The fourth planet from the Sun")
                }
        }
        let context = makeRenderContext(width: width, height: 8)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("The subtitle follows the title on the bar")
    func followsTheTitle() throws {
        let lines = bar(width: 70)
        let row = try #require(lines.first)
        let title = try #require(row.range(of: "Mars"))
        let subtitle = try #require(row.range(of: "The fourth planet from the Sun"))
        #expect(title.upperBound <= subtitle.lowerBound)
        #expect(lines.count >= 2 && lines[1].contains("─"), "the rule is still the bar's second row")
    }

    @Test("On a short row the subtitle truncates and the title does not")
    func truncatesFirst() throws {
        let lines = bar(width: 30)
        let row = try #require(lines.first)
        #expect(row.contains("Mars"), "the title keeps its room: \(row)")
        #expect(!row.contains("The fourth planet from the Sun"), "the subtitle gave way: \(row)")
        #expect(row.contains("Mars  The"), "still two cells after the title: \(row)")
        #expect(lines.count >= 2 && lines[1].contains("─"), "and the bar kept its height")
    }
}

@MainActor
@Suite("Navigation transition")
struct NavigationTransitionTests {
    @Test("The automatic transition is the one a stack makes: a pushed screen draws as it would without it")
    func automaticIsTheStacksOwn() {
        var path = NavigationPath()
        path.append(1)
        let binding = Binding(get: { path }, set: { path = $0 })
        let draw = { (withTransition: Bool) -> [String] in
            let view = NavigationStack(path: binding) {
                Text("root").navigationDestination(for: Int.self) { _ in
                    if withTransition {
                        Text("screen").navigationTransition(.automatic)
                    } else {
                        Text("screen")
                    }
                }
            }
            return renderToBuffer(view, context: makeRenderContext(width: 30, height: 6)).lines.map(\.stripped)
        }
        #expect(draw(true) == draw(false))
        #expect(draw(true).contains { $0.contains("screen") })
    }
}
