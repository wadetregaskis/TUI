//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListPinnedHeaderSeparatorTests.swift
//
//  A pinned section header covers the lines under it, and a row it covers
//  wholly or down to its separator draws nothing: the Lists page's
//  "Separators between rows" list showed `Files`, a rule, then the lone rule
//  of the row above `LICENSE`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("A pinned header leaves no lone separators under it")
struct ListPinnedHeaderSeparatorTests {
    private static let folders = ["Sources", "Tests", "docs", "plans", ".github", ".claude"]
    private static let files = ["README.md", "Package.swift", ".gitignore", "LICENSE", ".swiftlint.yml", "Makefile"]

    private final class Box: @unchecked Sendable {
        var selection: String?
    }

    /// The Lists page's sectioned list, as it draws with "Separators between
    /// rows" on: 8 lines, every row and section separator visible.
    private func sectioned(_ box: Box, style: some ListStyle) -> some View {
        List(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) {
            Section("Folders") { ForEach(Self.folders, id: \.self) { Text($0) } }
            Section("Files") { ForEach(Self.files, id: \.self) { Text($0) } }
        }
        .listRowSeparator(.visible)
        .listSectionSeparator(.visible)
        .listStyle(style)
        .frame(height: 8)
    }

    private func isRule(_ line: String) -> Bool {
        let text = line.stripped.trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && text.allSatisfy { $0 == "─" }
    }

    /// Every window of the list as the wheel scrolls it from the top to the
    /// bottom a line at a time, and back up.
    private func windows(style: some ListStyle) -> [[String]] {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        var frames = [harness.frame(sectioned(box, style: style)).lines.map(\.stripped)]
        for button in [MouseButton.scrollDown, .scrollUp] {
            for _ in 0..<40 {
                _ = harness.mouse(MouseEvent(button: button, phase: .scrolled, x: 2, y: 2))
                frames.append(harness.frame(sectioned(box, style: style)).lines.map(\.stripped))
            }
        }
        return frames
    }

    @Test("No window of the surface list has two rules in a row")
    func noAdjacentRules() {
        for window in windows(style: .surface) {
            let rules = window.map(isRule)
            #expect(!zip(rules, rules.dropFirst()).contains { $0 && $1 }, "\(window)")
        }
    }

    @Test("No window of the surface list shows a rule straight under its pinned header")
    func noRuleUnderThePinnedHeader() {
        for window in windows(style: .surface) {
            guard let top = window.first, top.contains("Files") || top.contains("Folders") else { continue }
            // The header's own rule is the second line; a third that is a rule
            // too is a separator of a row the header covers.
            #expect(window.count < 3 || !(isRule(window[1]) && isRule(window[2])), "\(window)")
        }
    }

    @Test("At the end the pinned header is followed by a row, and the last row is still reached")
    func endOfTheList() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        var window = harness.frame(sectioned(box, style: .surface)).lines.map(\.stripped)
        for _ in 0..<40 {
            _ = harness.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
            window = harness.frame(sectioned(box, style: .surface)).lines.map(\.stripped)
        }
        #expect(window.first?.contains("Files") == true, "\(window)")
        #expect(window.contains { $0.contains("Makefile") }, "\(window)")
        #expect(window.dropFirst(2).first?.contains("LICENSE") == true, "a row's text under the header's rule: \(window)")
    }

    @Test("A header with no rule of its own leaves the first row's rule alone")
    func headerWithoutARule() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let view = {
            List(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) {
                Section("Folders") { ForEach(Self.folders, id: \.self) { Text($0) } }
                Section("Files") { ForEach(Self.files, id: \.self) { Text($0) } }
            }
            .listRowSeparator(.visible)
            .listSectionSeparator(.hidden, edges: .top)
            .listStyle(.surface)
            .frame(height: 8)
        }
        _ = harness.frame(view())
        for _ in 0..<40 {
            _ = harness.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
            let window = harness.frame(view()).lines.map(\.stripped)
            let rules = window.map(isRule)
            #expect(!zip(rules, rules.dropFirst()).contains { $0 && $1 }, "\(window)")
        }
    }

    @Test("The same holds in the plain style")
    func plainStyle() {
        for window in windows(style: .plain) {
            let rules = window.map(isRule)
            #expect(!zip(rules, rules.dropFirst()).contains { $0 && $1 }, "\(window)")
        }
    }
}
