//  🖥️ TUI — A Terminal UI framework for Swift
//  ModifiedSectionRowsTests.swift
//
//  A `Section` under an environment write — or a padding, a container value,
//  an observable object, a text-selection scope — is still a section to its
//  `List`: its header and each of its rows rows of the list. The list drew
//  such a section as ONE row, so `Section { … }.headerProminence(.increased)`
//  lost its rows' badges, their tags and with them the selection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIFoundation
import TUILists
@testable import TUITestSupport

@Observable
private final class SectionModel {}

private struct SectionMarkKey: ContainerValueKey {
    static let defaultValue = 0
}

extension ContainerValues {
    fileprivate var sectionMark: Int {
        get { self[SectionMarkKey.self] }
        set { self[SectionMarkKey.self] = newValue }
    }
}

@MainActor
@Suite("A section under an environment write")
struct ModifiedSectionRowsTests {

    private func lines(_ view: some View) -> [String] {
        renderToBuffer(view.frame(width: 30, height: 6), context: makeRenderContext(width: 30, height: 6))
            .lines.map(\.stripped)
    }

    /// The second frame of `view`, by when the list holds the focus that the
    /// first gave it — and its section's actions show (owner ruling
    /// B78-VISIBILITY).
    private func focusedLines(_ view: some View) -> [String] {
        let context = makeRenderContext(width: 30, height: 6)
        _ = renderToBuffer(view.frame(width: 30, height: 6), context: context)
        return renderToBuffer(view.frame(width: 30, height: 6), context: context).lines.map(\.stripped)
    }

    @Test("Its rows keep their badges", arguments: [false, true])
    func badges(transformed: Bool) {
        let section = Section("Inbox") { Text("Unread").badge(3) }
        let drawn = transformed
            ? lines(List { section.transformEnvironment(\.headerProminence) { $0 = .increased } })
            : lines(List { section.headerProminence(.increased) })
        #expect(drawn.contains { $0.contains("Unread") && $0.contains("3") }, "\(drawn)")
    }

    /// `.sectionActions` written after the environment write wraps the
    /// modified section, so the list reaches the actions only if it sees the
    /// section through the write as well (decisions B78 recorded this shape
    /// drawing without its actions, before the write was seen through).
    @Test("Actions written after the environment write are drawn on its header's line", arguments: [false, true])
    func sectionActions(transformed: Bool) {
        let section = Section("Inbox") { Text("Unread") }
        let drawn = transformed
            ? focusedLines(
                List {
                    section.transformEnvironment(\.headerProminence) { $0 = .increased }
                        .sectionActions { Text("Act") }
                })
            : focusedLines(List { section.headerProminence(.increased).sectionActions { Text("Act") } })
        #expect(drawn.contains { $0.contains("Inbox") && $0.contains("Act") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("Unread") && !$0.contains("Inbox") }, "the row is its own: \(drawn)")
    }

    @Test("Its rows keep their tags, so the selection is drawn on the row it names")
    func tags() throws {
        let buffer = renderToBuffer(
            List(selection: .constant(Optional("b"))) {
                Section("S") {
                    Text("a").tag("a")
                    Text("b").tag("b")
                }
                .headerProminence(.increased)
            }
            .frame(width: 30, height: 6),
            context: makeRenderContext(width: 30, height: 6))
        let row = try #require(buffer.lines.first { $0.stripped.contains("b") && !$0.stripped.contains("S") })
        let other = try #require(buffer.lines.first { $0.stripped.contains("a") && !$0.stripped.contains("S") })
        #expect(row != other.replacingOccurrences(of: "a", with: "b"), "the selected row is drawn as selected")
        #expect(row.stripped.contains("●"), "the selected row carries its mark: \(row.stripped)")
    }

    // MARK: - Under the other wrappers a section can carry

    /// The wrappers other than an environment write that a `Section` can
    /// carry and still be a section to every other container
    /// (`SectionPartsProviding`): each is still a section to its `List`,
    /// where each was drawn as ONE row.
    enum Wrapper: String, CaseIterable {
        case padding, containerValue, observableObject, textSelection
    }

    /// `section` under `wrapper` — a `switch`, which a list looks through to
    /// the arm it takes, as it does an `if`/`else`.
    @ViewBuilder
    private func wrapped(_ section: some View, in wrapper: Wrapper) -> some View {
        switch wrapper {
        case .padding: section.padding(.leading, 1)
        case .containerValue: section.containerValue(\.sectionMark, 1)
        case .observableObject: section.environment(SectionModel())
        case .textSelection: section.textSelection(.enabled)
        }
    }

    @Test("Its rows keep their badges under any section wrapper", arguments: Wrapper.allCases)
    func badgesUnder(_ wrapper: Wrapper) {
        let drawn = lines(List { wrapped(Section("Inbox") { Text("Unread").badge(3) }, in: wrapper) })
        #expect(drawn.contains { $0.contains("Unread") && $0.contains("3") }, "\(wrapper): \(drawn)")
        #expect(drawn.contains { $0.contains("Inbox") && !$0.contains("Unread") }, "the header is its own row: \(drawn)")
    }

    @Test("Its rows keep their tags, so the selection is drawn on the row it names, under any section wrapper",
          arguments: Wrapper.allCases)
    func tagsUnder(_ wrapper: Wrapper) throws {
        let buffer = renderToBuffer(
            List(selection: .constant(Optional("b"))) {
                wrapped(Section("S") { Text("a").tag("a"); Text("b").tag("b") }, in: wrapper)
            }
            .frame(width: 30, height: 6),
            context: makeRenderContext(width: 30, height: 6))
        let row = try #require(buffer.lines.first { $0.stripped.contains("b") && !$0.stripped.contains("S") })
        #expect(row.stripped.contains("●"), "\(wrapper): the selected row carries its mark: \(row.stripped)")
    }

    /// A buffer modifier on the section reaches each part: the header and
    /// every row drawn padded, as each part of a section in a stack is.
    @Test("A padding on the section pads its header and each of its rows")
    func paddingReachesEachRow() throws {
        let plain = lines(List { Section("Head") { Text("one"); Text("two") } })
        let padded = lines(List { Section("Head") { Text("one"); Text("two") }.padding(.leading, 2) })
        for word in ["Head", "one", "two"] {
            let before = try #require(plain.first { $0.contains(word) }, "\(plain)")
            let after = try #require(padded.first { $0.contains(word) }, "\(padded)")
            let column = { (line: String) in line.distance(from: line.startIndex, to: line.range(of: word)!.lowerBound) }
            #expect(column(after) == column(before) + 2, "\(word) is padded: \(padded)")
        }
    }
}
