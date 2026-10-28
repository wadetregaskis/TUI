//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlsClip.swift
//
//  `controls`: an event planner used from the keyboard — a field typed into,
//  time fields that grey out when the event is all day, a pop-up menu picker,
//  a switch, a stepper whose gauge follows, a slider, a segmented control, a
//  colour from the colour panel, and a day chosen on a calendar whose weekend
//  and past days have tones of their own — every key through TUI's own
//  input path.
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

/// Names the event, nudges its start and end, makes it all day (the times
/// grey out), picks how it repeats from a pop-up, adds guests (the gauge
/// follows), sets what each chips in on a slider, an alert on a segmented
/// control, a label colour in the colour panel, and walks the calendar to its
/// day: one Tab to each control, in the form's order, the calendar last.
private func controlsScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 90, height: 25)), .wait(0.6)]
    script += Step.type("Launch party", interval: 0.07)
    // Past the place, already filled in, to the start: an hour later; the
    // end, an hour later too.
    script += [.wait(0.3), .tab, .wait(0.15), .tab, .wait(0.3), .up, .wait(0.4), .tab, .wait(0.3), .up, .wait(0.5)]
    // All day, on: the two times grey out.
    script += [.tab, .wait(0.3), .space, .wait(0.8)]
    // Repeat: the pop-up, two down, chosen.
    script += [.tab, .wait(0.3), .space, .wait(0.6), .down, .wait(0.3), .down, .wait(0.4), .enter, .wait(0.6)]
    // Guests, up by five; the gauge fills.
    script += [.tab, .wait(0.3)]
    script += Step.repeat(.right, 5, interval: 0.25)
    // What each chips in, up three steps.
    script += [.wait(0.2), .tab, .wait(0.3)]
    script += Step.repeat(.right, 3, interval: 0.3)
    // An alert a day before: the arrows move the segmented control's cursor,
    // Space chooses.
    script += [.wait(0.3), .tab, .wait(0.3), .right, .wait(0.4), .right, .wait(0.3), .space, .wait(0.6)]
    // The label colour: its panel opens on the hex field; a new colour typed
    // over the digits (the field takes it as it is typed), and Done — the
    // stop before the field, a Shift-Tab away — pressed. (Return in the field
    // goes on to the tabs, and Escape is Cancel, which puts the old colour
    // back.)
    script += [.tab, .wait(0.3), .enter, .wait(1.0)]
    script += Step.repeat(.keys("\u{7F}"), 6, interval: 0.06)
    script += Step.type("E8A33D", interval: 0.12)
    script += [.wait(0.7), .backTab, .wait(0.5), .enter, .wait(0.8)]
    // The calendar: three days on, a week down, chosen.
    script += [.tab, .wait(0.4)]
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
/// field and a toggle — time fields, a pop-up menu, a switch, a stepper
/// driving a gauge, a slider, a calendar and the colour panel — with the
/// invitation they make beside them, and below, the evening's notes and who
/// is invited: a planner as full as a real one fills the 16:10 frame.
struct EventPlanner: View {
    @State private var title = ""
    @State private var date = Self.start
    @State private var starts = Self.time(18)
    @State private var ends = Self.time(22)
    @State private var repeats = "Never"
    @State private var allDay = false
    @State private var place = "The Boathouse"
    @State private var alert = "None"
    @State private var guests = 12
    @State private var chipIn = 10.0
    @State private var colour = Color(red: 0.36, green: 0.55, blue: 0.95)
    @State private var notes = """
        6:00  Drinks on the deck
        7:00  Dinner in the long room
        8:30  Slides, and the thank-yous
        9:30  Music until late

        Bring the slides and the clicker.
        RSVP by Friday, please.
        """
    /// Who is on the list so far: the rest are suggestions, dimmed.
    @State private var invitees: Set<String> = ["Ada Lovelace", "Grace Hopper", "Alan Turing"]

    private let people = ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson", "Claude Shannon"]

    /// The calendar opens four days from today, so the month it shows has
    /// days gone by (faint) and days to come.
    static let start: Date = {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: DateComponents(day: 4, hour: 18), to: today) ?? today
    }()

    /// `hour` o'clock on the event's day.
    static func time(_ hour: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? start
    }

    private let rules = ["Never", "Daily", "Weekly", "Monthly", "Yearly"]
    private let alerts = ["None", "1 h", "1 day"]

    /// The right-hand column's width: from where it begins to the camera's
    /// right edge, so the cards end neatly at the frame.
    private static let cardWidth = 31

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 2) {
                    form
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .datePickerDistinguishesPastDays()
                        .labelsHidden()
                        .fixedSize()
                }
                GroupBox("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 10)
                }
                .frame(width: 56)
            }
            VStack(alignment: .leading, spacing: 1) {
                invitation
                GroupBox("Invitees") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(people, id: \.self) { name in
                            let invited = invitees.contains(name)
                            Toggle(isOn: Binding(
                                get: { invited },
                                set: { if $0 { invitees.insert(name) } else { invitees.remove(name) } })
                            ) {
                                Text(verbatim: name)
                                    .foregroundStyle(invited ? .palette.foreground : .palette.foregroundTertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.cardWidth)
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
            DatePicker("Starts", selection: $starts, displayedComponents: .hourAndMinute)
                .disabled(allDay)
            DatePicker("Ends", selection: $ends, displayedComponents: .hourAndMinute)
                .disabled(allDay)
            Toggle("All day", isOn: $allDay)
                .toggleStyle(.switch)
            Picker("Repeat", selection: $repeats) {
                ForEach(rules, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Stepper("Guests", value: $guests, in: 0...40)
            LabeledContent("Chip in") { Slider(value: $chipIn, in: 0...50, step: 5) }
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

    /// What the form makes: the invitation, live, in a few voices — the day
    /// in the label's colour, the hours in italics, how it repeats quieter,
    /// the place underlined as a link would be.
    private var invitation: some View {
        GroupBox("Invitation") {
            // As wide as the column, whatever it says: a box sized to its words
            // changed width as the title was typed.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text(verbatim: "  ").background(colour)
                    Text(verbatim: title.isEmpty ? "Untitled event" : title).bold()
                }
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .bold()
                    .foregroundStyle(colour)
                Group {
                    if allDay {
                        Text(verbatim: "All day")
                    } else {
                        Text(verbatim: "\(starts.formatted(date: .omitted, time: .shortened)) – "
                            + ends.formatted(date: .omitted, time: .shortened))
                    }
                }
                .italic()
                .foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: repeats == "Never" ? "Once" : "Repeats \(repeats.lowercased())")
                    .foregroundStyle(.palette.foregroundTertiary)
                HStack(spacing: 1) {
                    Text(verbatim: place).underline()
                    if alert != "None" {
                        Text(verbatim: "· \(alert) alert").foregroundStyle(.palette.foregroundSecondary)
                    }
                }
                HStack(alignment: .center, spacing: 3) {
                    Gauge(value: Double(guests), in: 0...40) {
                        Text(verbatim: "Guests")
                    } currentValueLabel: {
                        Text(verbatim: "\(guests)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(colour)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Chip in").foregroundStyle(.palette.foregroundTertiary)
                        Text(verbatim: "$\(Int(chipIn)) each").bold()
                    }
                }
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.cardWidth)
    }
}
