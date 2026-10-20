//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

// MARK: - Picker Rows

/// The selection controls no other scenario draws: a graphical `DatePicker`,
/// a `RadioButtonGroup` and a grouped `Form` (decisions SPB7, B-SPB7-4).
///
/// `rows` is the default, so the sweep runs it: rows of a segmented `Picker`
/// and a horizontal `RadioButtonGroup`, every fourth with a graphical
/// `DatePicker` under it — a month's calendar, the date picker's per-cell
/// calls. The selections move with the tick, so no memo serves a row.
/// `grouped-form` is a `Form` in `.formStyle(.grouped)` whose sections
/// alternate an `if`, so a section appears and disappears every frame.
enum PickerRowsMatrix {
    static let scenarioID = "pickers"

    @MainActor
    static let descriptor = Scenario(
        id: scenarioID,
        title: "Picker Rows",
        blurb: "Segmented pickers, radio groups and graphical date pickers in rows, or a grouped Form.",
        stresses: "segmented and radio selection · a graphical date picker's calendar · grouped form sections",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.pickers.heading", "?", 0)))
        }
    )

    private static func variant(
        _ id: String, _ summary: String, _ make: @escaping @MainActor (StressConfig) -> AnyView
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: "picker", make: make)
    }

    @MainActor
    static let variants: [ScenarioVariant] = [
        variant("rows", "segmented pickers and radio groups, a graphical DatePicker under every fourth row") { config in
            AnyView(PickerRowsView(config: config))
        },
        variant("grouped-form", "a grouped Form whose sections hold pickers, and alternate an if section") { config in
            AnyView(GroupedPickerForm(config: config))
        },
    ]
}

/// A date the tick moves by a day, from a fixed epoch so every run draws the
/// same months.
private func tickedDate(_ h: UInt64) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + Double(h % 400) * 86_400)
}

private struct PickerRowsView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(24)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.pickers.heading", "rows", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        PickerRow(index: index, h: mix(config.seed, index &+ tick))
                    }
                }
            }
        }
    }
}

private struct PickerRow: View {
    let index: Int
    let h: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text(verbatim: Synth.slug(h))
                Picker("Mode", selection: .constant(Int(h % 3))) {
                    Text("Day").tag(0)
                    Text("Week").tag(1)
                    Text("Month").tag(2)
                }
                .pickerStyle(.segmented)
            }
            RadioButtonGroup(selection: .constant(Int((h >> 8) % 3)), orientation: .horizontal) {
                RadioButtonItem(0, "Low")
                RadioButtonItem(1, "Normal")
                RadioButtonItem(2, "High")
            }
            if index.isMultiple(of: 4) {
                DatePicker("Due", selection: .constant(tickedDate(h)), displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
        }
    }
}

/// Sections of pickers in a grouped form; every other section is behind an
/// `if` the tick flips.
private struct GroupedPickerForm: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let sections = config.sized(12)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.pickers.heading", "grouped-form", sections)).bold()
            Form {
                ForEach(0..<sections, id: \.self) { section in
                    let h = mix(config.seed, section &+ tick)
                    if section.isMultiple(of: 2) || tick.isMultiple(of: 2) {
                        Section(Synth.name(h)) {
                            Picker("Priority", selection: .constant(Int(h % 3))) {
                                Text("Low").tag(0)
                                Text("Normal").tag(1)
                                Text("High").tag(2)
                            }
                            Toggle("Notify", isOn: .constant(h.isMultiple(of: 2)))
                            DatePicker("Due", selection: .constant(tickedDate(h)), displayedComponents: .date)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
