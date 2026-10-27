//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlsClip.swift
//
//  `controls`: an event planner used from the keyboard — a field typed into,
//  a pop-up menu picker, a switch, a stepper whose gauges follow, a segmented
//  control, and a day chosen on a calendar — every key through TUI's own input path.
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
    // As tall as a 16:10 frame of the planner needs.
    rows: 30,
    output: 800,
    script: controlsScript(),
    run: { await ControlsApp.main() }
)

/// Names the event, picks how it repeats from a pop-up, flips a switch, adds
/// guests (the gauges follow), sets an alert on a segmented control, and walks
/// the calendar to its day: one Tab to each control, in the form's order, the
/// calendar last, beside the form.
private func controlsScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 90, height: 25)), .wait(0.6)]
    script += Step.type("Launch party", interval: 0.07)
    // Past the place, already filled in, to Repeat: the pop-up, two down, chosen.
    script += [.wait(0.3), .tab, .wait(0.15), .tab, .wait(0.3), .space, .wait(0.6), .down, .wait(0.3), .down, .wait(0.4), .enter, .wait(0.6)]
    // All day, on.
    script += [.tab, .wait(0.3), .space, .wait(0.6)]
    // Guests, up by five; the gauges fill.
    script += [.tab, .wait(0.3)]
    script += Step.repeat(.right, 5, interval: 0.3)
    // An alert a day before: the arrows move the segmented control's cursor,
    // Space chooses.
    script += [.wait(0.3), .tab, .wait(0.3), .right, .wait(0.4), .right, .wait(0.3), .space, .wait(0.6)]
    // The calendar, past the label's swatch: three days on, a week down,
    // chosen. (The swatch's colour panel is a dialog taller than the whole
    // clip, so the clip leaves it shut.)
    script += [.wait(0.4), .tab, .wait(0.2), .tab, .wait(0.4)]
    script += Step.repeat(.right, 3, interval: 0.25)
    script += [.down, .wait(0.35), .space, .wait(1.4)]
    return script
}

struct ControlsApp: App {
    var body: some Scene {
        WindowGroup("TUI · Planner") {
            EventPlanner()
                .palette(AppleTerminalPalette(.solidColors))
        }
    }
}

/// An event planner: the built-in controls a real form reaches for, beyond a
/// field and a toggle — a calendar, a pop-up menu, a switch, a stepper
/// driving gauges, and the colour panel — with what they make beside them,
/// and below, the evening's notes and who has said they will come: a planner
/// as full as a real one fills the 16:10 frame.
struct EventPlanner: View {
    @State private var title = ""
    @State private var date = Self.start
    @State private var repeats = "Never"
    @State private var allDay = false
    @State private var place = "The Boathouse"
    @State private var alert = "None"
    @State private var guests = 12
    @State private var colour = Color(red: 0.36, green: 0.55, blue: 0.95)
    @State private var notes = """
        6:00  Drinks on the deck
        7:00  Dinner in the long room
        8:30  Slides, and the thank-yous
        9:30  Music until late

        Bring the slides and the clicker.
        RSVP by Friday, please.
        """
    /// Who has said they will come, by name.
    @State private var coming: Set<String> = ["Ada Lovelace", "Grace Hopper", "Alan Turing"]

    private let invited = ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson", "Claude Shannon"]

    /// The calendar opens on 14 November 2026, the same every run.
    static let start: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour) = (2026, 11, 14, 18)
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    private let rules = ["Never", "Daily", "Weekly", "Monthly", "Yearly"]
    private let alerts = ["None", "1 h", "1 day"]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .top, spacing: 2) {
                        form
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .fixedSize()
                    }
                    GroupBox("Notes") {
                        TextEditor(text: $notes)
                            .frame(height: 9)
                    }
                    .frame(width: 56)
                }
                VStack(alignment: .leading, spacing: 1) {
                    invitation
                    GroupBox("Coming") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(invited, id: \.self) { name in
                                Toggle(name, isOn: Binding(
                                    get: { coming.contains(name) },
                                    set: { if $0 { coming.insert(name) } else { coming.remove(name) } }))
                            }
                        }
                    }
                    .frame(width: 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "New event") }
        }
    }

    /// The fields, labels right-aligned to a shared pillar with their
    /// controls close beside them: the classic macOS form, compact.
    private var form: some View {
        Form {
            LabeledContent("Event") { TextField("Name", text: $title) }
            LabeledContent("Where") { TextField("Place", text: $place) }
            Picker("Repeat", selection: $repeats) {
                ForEach(rules, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Toggle("All day", isOn: $allDay)
                .toggleStyle(.switch)
            Stepper("Guests", value: $guests, in: 0...40)
            Picker("Alert", selection: $alert) {
                ForEach(alerts, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            ColorPicker("Label", selection: $colour, supportsOpacity: false)
                .colorPickerChannels(.hidden)
        }
        .formStyle(.columns)
        .frame(width: 32)
    }

    /// What the form makes: the invitation, live.
    private var invitation: some View {
        GroupBox("Invitation") {
            VStack(alignment: .leading, spacing: 0) {
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
                Text(verbatim: alert == "None" ? place : "\(place) · \(alert) alert")
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
                    .frame(width: 14)
                }
                .padding(.top, 1)
            }
        }
        .frame(width: 32)
    }
}
