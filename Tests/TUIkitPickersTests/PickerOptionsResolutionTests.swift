//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerOptionsResolutionTests.swift
//
//  A picker finds its options where SwiftUI finds them (deviation V7, fixed by
//  the owner's ruling of 2026-10-13). It used to ask its content's TYPE, and
//  only seven types answered — a tagged view, a `Divider`, `EmptyView`, a
//  tuple, a `ForEach`, an `if`/`else` and an `if` — so options inside a view
//  of the app's own, a `Section`, a `Group` or an `AnyView`, and an option
//  with a modifier after its `.tag(_:)`, were not there: the picker drew
//  fewer options or none, with no warning. It now reads its content's
//  members, as `Group(subviews:)` resolves them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitPickers
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("A picker's options, wherever they are written")
struct PickerOptionsResolutionTests {
    private enum Flavor: String, CaseIterable, Identifiable {
        case chocolate, vanilla, strawberry
        var id: Self { self }
    }

    /// Options in a view of the app's own.
    private struct FlavorOptions: View {
        var body: some View {
            ForEach(Flavor.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
    }

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 12)).lines.map(\.stripped)
    }

    /// The options a radio-group picker over `content` draws, marked one first.
    private func drawn<Content: View>(
        selecting selection: Flavor, @ViewBuilder _ content: () -> Content
    ) -> (all: [String], marked: String?) {
        let picker = Picker("Flavor", selection: .constant(selection), content: content).pickerStyle(.radioGroup)
        let drawn = lines(picker).filter {
            $0.contains(TerminalSymbols.radioSelected) || $0.contains(TerminalSymbols.radioUnselected)
        }
        return (drawn, drawn.first { $0.contains(TerminalSymbols.radioSelected) })
    }

    @Test("Options inside a view of the app's own are found, and select")
    func appsOwnView() {
        let result = drawn(selecting: .vanilla) { FlavorOptions() }
        #expect(result.all.count == 3, "\(result.all)")
        #expect(result.marked?.contains("Vanilla") == true)
    }

    @Test("Options inside a Group or an AnyView are found")
    func groupAndAnyView() {
        let grouped = drawn(selecting: .chocolate) {
            Group {
                Text("Chocolate").tag(Flavor.chocolate)
                Text("Vanilla").tag(Flavor.vanilla)
            }
        }
        #expect(grouped.all.count == 2, "\(grouped.all)")
        let erased = drawn(selecting: .vanilla) {
            AnyView(Text("Vanilla").tag(Flavor.vanilla))
            Text("Strawberry").tag(Flavor.strawberry)
        }
        #expect(erased.all.count == 2, "\(erased.all)")
        #expect(erased.marked?.contains("Vanilla") == true)
    }

    @Test("A modifier written after the tag keeps the option")
    func modifierAfterTag() {
        let result = drawn(selecting: .strawberry) {
            Text("Chocolate").tag(Flavor.chocolate).bold()
            Text("Strawberry").tag(Flavor.strawberry).padding(.leading, 1)
        }
        #expect(result.all.count == 2, "\(result.all)")
        #expect(result.marked?.contains("Strawberry") == true)
    }

    @Test("Each section's options are found, and a menu sets the sections apart with a rule")
    func sections() {
        let options = _PickerOptionsReader<Flavor, _, EmptyView>(
            content: Group {
                Section("Dark") { Text("Chocolate").tag(Flavor.chocolate) }
                Section("Light") {
                    Text("Vanilla").tag(Flavor.vanilla)
                    Text("Strawberry").tag(Flavor.strawberry)
                }
            }
        ) { _, _ in EmptyView() }
        .entries(in: makeRenderContext(width: 40, height: 12))
        // Each section's header is its group's title (`PickerSectionTitleTests`),
        // the first's at the top, where the rule before it collapses.
        #expect(options.map(\.tag) == [nil, .chocolate, nil, nil, .vanilla, .strawberry], "\(options.map(\.tag))")
    }

    @Test("A Divider is a rule, never an option, and none is left at an edge or doubled")
    func dividers() {
        let options = _PickerOptionsReader<Flavor, _, EmptyView>(
            content: Group {
                Divider()
                Text("Chocolate").tag(Flavor.chocolate)
                Divider()
                Divider()
                Text("Vanilla").tag(Flavor.vanilla)
                Divider()
            }
        ) { _, _ in EmptyView() }
        .entries(in: makeRenderContext(width: 40, height: 12))
        #expect(options.map(\.tag) == [.chocolate, nil, .vanilla])
    }

    @Test("An untagged ForEach row is tagged with its element's id, and an untagged view is no option, reported")
    func implicitAndMissingTags() {
        let reports = DroppedMemberReports()
        let result = DroppedMember.$reporter.withValue(reports.record) {
            drawn(selecting: .strawberry) {
                Text("Pick one")
                ForEach(Flavor.allCases) { Text($0.rawValue.capitalized) }
            }
        }
        #expect(result.all.count == 3, "the untagged Text was taken for an option: \(result.all)")
        #expect(result.marked?.contains("Strawberry") == true)
        // SwiftUI shows it, as an item of the menu (owner ruling RC5).
        #expect(!reports.messages.isEmpty && reports.messages.allSatisfy { $0.hasPrefix("Picker leaves out a Text") })
    }

    @Test("A member tagged with another type than the selection's is reported as left out; a divider is not")
    func wrongTypeReported() {
        let reports = DroppedMemberReports()
        let result = DroppedMember.$reporter.withValue(reports.record) {
            drawn(selecting: .chocolate) {
                Text("Chocolate").tag(Flavor.chocolate)
                Divider()
                Text("Two").tag(2)
            }
        }
        #expect(result.all.count == 1, "\(result.all)")
        #expect(reports.messages.count >= 1 && reports.messages.allSatisfy { $0.contains("Flavor") }, "\(reports.messages)")
        let quiet = DroppedMemberReports()
        _ = DroppedMember.$reporter.withValue(quiet.record) {
            drawn(selecting: .chocolate) {
                Text("Chocolate").tag(Flavor.chocolate)
                Divider()
                Text("Vanilla").tag(Flavor.vanilla)
            }
        }
        #expect(quiet.messages.isEmpty, "\(quiet.messages)")
    }

    @Test("Only the branch an if takes contributes options")
    func conditional() {
        func options(dark: Bool) -> [String] {
            drawn(selecting: .chocolate) {
                if dark {
                    Text("Chocolate").tag(Flavor.chocolate)
                } else {
                    Text("Vanilla").tag(Flavor.vanilla)
                    Text("Strawberry").tag(Flavor.strawberry)
                }
            }.all
        }
        #expect(options(dark: true).count == 1)
        #expect(options(dark: false).count == 2)
    }
}
