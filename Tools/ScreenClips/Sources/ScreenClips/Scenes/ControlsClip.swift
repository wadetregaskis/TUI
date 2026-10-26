//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlsClip.swift
//
//  `controls`: an event planner used from the keyboard — a field typed into,
//  a day chosen on a calendar, a pop-up menu picker, a switch, a stepper
//  whose gauges follow, and a colour from the colour panel — every key
//  through TUI's own input path.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let controlsClip = Clip(
    id: "controls",
    title: "Controls",
    columns: 112,
    rows: 30,
    output: 800,
    script: controlsScript(),
    run: { await ControlsApp.main() }
)

/// Names the event, walks the calendar to its day, picks how it repeats from
/// a pop-up, flips a switch, adds guests (the gauges follow), and gives it a
/// colour from the colour panel: one Tab to each control, in the form's order.
private func controlsScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 96, height: 24)), .wait(0.6)]
    script += Step.type("Launch party", interval: 0.07)
    // The calendar: three days on, a week down, chosen.
    script += [.wait(0.3), .tab, .wait(0.4)]
    script += Step.repeat(.right, 3, interval: 0.25)
    script += [.down, .wait(0.35), .space, .wait(0.6)]
    // Repeat: the pop-up, two down, chosen.
    script += [.tab, .wait(0.3), .space, .wait(0.6), .down, .wait(0.3), .down, .wait(0.4), .enter, .wait(0.6)]
    // All day, on.
    script += [.tab, .wait(0.3), .space, .wait(0.6)]
    // Guests, up by five; the gauges fill.
    script += [.tab, .wait(0.3)]
    script += Step.repeat(.right, 5, interval: 0.3)
    // The label colour: its panel opens on the hex field; a new colour typed
    // over the digits, and Done clicked (cell 63, 25, read from the film).
    script += [.wait(0.3), .tab, .wait(0.3), .enter, .wait(1.0)]
    script += Step.repeat(.keys("\u{7F}"), 6, interval: 0.06)
    script += Step.type("E8A33D", interval: 0.12)
    script += [.enter, .wait(0.9)]
    script += Step.click(63, 25)
    script += [.wait(1.4)]
    return script
}

struct ControlsApp: App {
    var body: some Scene {
        WindowGroup("TUI · Planner") {
            EventPlanner()
                .palette(AppleTerminalPalette(.redSands))
        }
    }
}

/// An event planner: the built-in controls a real form reaches for, beyond a
/// field and a toggle — a calendar, a pop-up menu, a switch, a stepper
/// driving gauges, and the colour panel — with what they make beside them.
struct EventPlanner: View {
    @State private var title = ""
    @State private var date = Self.start
    @State private var repeats = "Never"
    @State private var allDay = false
    @State private var guests = 12
    @State private var colour = Color(red: 0.36, green: 0.55, blue: 0.95)

    /// The calendar opens on 14 November 2026, the same every run.
    static let start: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 11, 14, 18)
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    private let rules = ["Never", "Daily", "Weekly", "Monthly", "Yearly"]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            form
            invitation
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "New event") }
        }
    }

    private var form: some View {
        Form {
            LabeledContent("Event") { TextField("Name", text: $title) }
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
            Picker("Repeat", selection: $repeats) {
                ForEach(rules, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Toggle("All day", isOn: $allDay)
                .toggleStyle(.switch)
            Stepper("Guests: \(guests)", value: $guests, in: 0...40)
            ColorPicker("Label", selection: $colour, supportsOpacity: false)
                .colorPickerChannels(.hidden)
        }
        .formStyle(.grouped)
        .frame(width: 52)
    }

    /// What the form makes: the invitation, live.
    private var invitation: some View {
        GroupBox("Invitation") {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text(verbatim: "  ").background(colour)
                    Text(verbatim: title.isEmpty ? "Untitled event" : title).bold()
                }
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: allDay ? "All day" : "18:00 – 23:00")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: repeats == "Never" ? "Once" : "Repeats \(repeats.lowercased())")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 2) {
                    Gauge(value: Double(guests), in: 0...40) {
                        Text(verbatim: "Guests")
                    } currentValueLabel: {
                        Text(verbatim: "\(guests)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(colour)
                    Gauge(value: Double(guests) * 18, in: 0...720) {
                        Text(verbatim: "Budget")
                    } currentValueLabel: {
                        Text(verbatim: "$\(guests * 18)")
                    }
                    .gaugeStyle(.linearCapacity)
                    .tint(colour)
                    .frame(width: 16)
                }
            }
        }
        .frame(width: 34)
    }
}
