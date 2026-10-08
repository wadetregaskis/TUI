//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToggleSourcesTests.swift
//
//  `Toggle(sources:isOn:)`: one toggle for many values — on when all are, off
//  when none is, mixed between — and activating it sets them all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

private struct Alarm: Hashable, Identifiable {
    var id: Int
    var isOn: Bool
}

/// The alarms the toggles under test stand for.
private final class AlarmStore: @unchecked Sendable {
    var alarms: [Alarm]
    init(_ states: [Bool]) {
        alarms = states.enumerated().map { Alarm(id: $0.offset, isOn: $0.element) }
    }
    var binding: Binding<[Alarm]> {
        Binding(get: { self.alarms }, set: { self.alarms = $0 })
    }
}

/// Reports whether its configuration is mixed.
private struct MixedReportingStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text(configuration.isMixed ? "mixed" : configuration.isOn ? "on" : "off")
    }
}

@MainActor
@Suite("Toggle(sources:isOn:)")
struct ToggleSourcesTests {
    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 2)).lines.first?.stripped ?? ""
    }

    @Test("On when every source is, off when none is, mixed between")
    func states() {
        func drawn(_ states: [Bool]) -> String {
            line(Toggle("All", sources: AlarmStore(states).binding, isOn: \.isOn).toggleStyle(.checkbox))
        }
        let on = drawn([true, true])
        let off = drawn([false, false])
        let mixed = drawn([true, false])
        #expect(on.contains("\u{25A0}") && off.contains("\u{25A1}"), "\(on) / \(off)")
        #expect(mixed.contains("\u{229F}"), "a mixed checkbox shows the squared minus: \(mixed)")
        #expect(mixed.count == on.count, "and takes the room the others do")

        let ascii = line(
            Toggle("All", sources: AlarmStore([true, false]).binding, isOn: \.isOn)
                .toggleStyle(.checkbox).toggleCharacterSet(.ascii))
        #expect(ascii.contains("[-]"), "\(ascii)")
    }

    @Test("A custom style sees isMixed")
    func customStyleSeesMixed() {
        #expect(line(Toggle(sources: AlarmStore([true, false]).binding, isOn: \.isOn) { Text("All") }
            .toggleStyle(MixedReportingStyle())) == "mixed")
        #expect(line(Toggle(sources: AlarmStore([true, true]).binding, isOn: \.isOn) { Text("All") }
            .toggleStyle(MixedReportingStyle())) == "on")
    }

    @Test("Activating a mixed toggle turns every source on; activating it again turns them off")
    func activation() {
        let store = AlarmStore([true, false, false])
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .enter)]) {
            Toggle("All", sources: store.binding, isOn: \.isOn)
        }
        #expect(store.alarms.map(\.isOn) == [true, true, true])
        harness.play([KeyEvent(key: .enter)]) {
            Toggle("All", sources: store.binding, isOn: \.isOn)
        }
        #expect(store.alarms.map(\.isOn) == [false, false, false])
    }

    @Test("With no sources the toggle is off")
    func noSources() {
        let empty = line(Toggle("None", sources: AlarmStore([]).binding, isOn: \.isOn).toggleStyle(.checkbox))
        #expect(empty.contains("\u{25A1}"))
    }
}
