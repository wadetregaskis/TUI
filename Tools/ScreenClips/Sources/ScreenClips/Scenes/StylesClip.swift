//  🖥️ TUI — A Terminal UI framework for Swift
//  StylesClip.swift
//
//  `styles`: one booking form, restyled under the person filling it in, in
//  one theme throughout — the palette and the boxes' borders never change;
//  that is the `theming` clip. What changes is the styles: the controls'
//  chrome (filled, lines, Braille dots, none), the class picker segmented, a
//  radio group or a pop-up, the extras switches, checkboxes or buttons, the
//  coach's gauge a bar or a ring, and the control size — each look named on
//  the form's last line by the modifiers that make it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let stylesClip = Clip(
    id: "styles",
    title: "Styles",
    columns: 112,
    rows: 30,
    output: 800,
    script: stylesScript(),
    run: { await StylesApp.main() }
)

/// A look every two seconds or so, and in each the booking taken a step on —
/// First class, a third passenger, the quiet coach, a bicycle, no window seat —
/// then a fresh form in the first look, as it began. The class picker has the
/// focus when the form opens.
private func stylesScript() -> [Step] {
    [
        .camera(Shot(x: 0, y: 2, width: 73, height: 21)), .wait(0.8),
        .right, .wait(0.3), .space, .wait(0.9),  // Standard → First
        .cue("look lines"), .wait(0.7), .tab, .wait(0.4), .right, .wait(0.9),  // 2 → 3 passengers
        .cue("look braille"), .wait(0.7),
        // Past the passenger's name, email and phone and the window seat.
        .tab, .wait(0.12), .tab, .wait(0.12), .tab, .wait(0.12), .tab, .wait(0.12), .tab,
        .wait(0.4), .space, .wait(0.9),  // the quiet coach
        .cue("look large"), .wait(0.7), .tab, .wait(0.4), .space, .wait(0.9),  // a bicycle…
        // …so not the window seat: the bicycle spaces are at the coach's end.
        // Then on, so the window seat shows unfocused: a toggle button off is
        // its plain label, and one focused is in the accent colour.
        .cue("look bare"), .wait(0.7), .backTab, .wait(0.15), .backTab, .wait(0.4), .space, .wait(0.4),
        .tab, .wait(0.7),
        .cue("look filled"), .cue("restart"), .wait(0.3),
    ]
}

/// The looks the clip walks, each a few style modifiers over TUI's defaults
/// (block controls, pop-up pickers, checkboxes, a bar gauge).
enum StyleLook: String, CaseIterable {
    case filled, lines, braille, large, bare

    var controlStyle: ControlStyle {
        switch self {
        case .filled, .large: .block
        case .lines: .lines
        case .braille: .braille
        case .bare: .blank
        }
    }

    var pickerStyle: any PickerStyle {
        switch self {
        case .filled, .large: .segmented
        case .lines: .radioGroup
        case .braille, .bare: .automatic
        }
    }

    var toggleStyle: any ToggleStyle {
        switch self {
        case .filled: .switch
        case .bare: .button
        case .lines, .braille, .large: .automatic  // a checkbox
        }
    }

    var gaugeStyle: any GaugeStyle { self == .braille ? .accessoryCircularCapacity : .automatic }
    var size: ControlSize { self == .large ? .large : .regular }

    /// What the form's last line says the look is made of: every modifier
    /// above that is not TUI's default — and, in the first look, the block
    /// control style that is, so the line names the axis the others change.
    var recipe: String {
        switch self {
        case .filled: ".controlStyle(.block)  .pickerStyle(.segmented)  .toggleStyle(.switch)"
        case .lines: ".controlStyle(.lines)  .pickerStyle(.radioGroup)"
        case .braille: ".controlStyle(.braille)  .gaugeStyle(.accessoryCircularCapacity)"
        case .large: ".controlSize(.large)  .pickerStyle(.segmented)  .textCase(.uppercase)"
        case .bare: ".controlStyle(.blank)  .toggleStyle(.button)"
        }
    }
}

struct StylesApp: App {
    @State private var look = StyleLook.filled
    /// A new booking each time the clip comes round: the form's state is made
    /// afresh.
    @State private var booking = 0

    var body: some Scene {
        WindowGroup("TUI · Styles") {
            BookingForm(look: look)
                .id(booking)
                .task {
                    for await cue in ClipCues.stream() {
                        if cue == "restart" {
                            booking += 1
                        } else if cue.hasPrefix("look "), let next = StyleLook(rawValue: String(cue.dropFirst(5))) {
                            look = next
                        }
                    }
                }
        }
        // One theme for the whole clip: only the styles change.
        .palette(AppleTerminalPalette(.basic))
    }
}

/// A train booking: the journey and how full the coach is, the lead
/// passenger and the extras, the railcard, the price and the two buttons.
struct BookingForm: View {
    let look: StyleLook
    @State private var seatClass = 0
    @State private var passengers = 2
    @State private var railcard = 0
    @State private var name = "Morag Campbell"
    @State private var email = "morag@example.com"
    @State private var phone = "07700 900123"
    @State private var window = true
    @State private var quiet = false
    @State private var bike = false

    /// Seats in coach C, and how many were taken before this booking.
    private static let coachSeats = 50
    private static let taken = 39
    private static let fares = [54, 129, 210]

    private var price: Int {
        let full = passengers * Self.fares[seatClass]
        return railcard == 0 ? full : full * 2 / 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            form
            // As low as it can go under the form: the large controls' extra
            // rows take up the gap.
            Spacer(minLength: 0)
            Text(verbatim: look.recipe)
                .textCase(nil)
                .fixedSize()
                .foregroundStyle(.palette.foregroundTertiary)
        }
        // The looks' styles, set as `.pickerStyle(_:)`, `.toggleStyle(_:)` and
        // `.gaugeStyle(_:)` set them — in the environment — but each as one
        // value whatever the look, so the form is one view throughout and
        // keeps its focus and state from look to look.
        .environment(\.pickerStyle, look.pickerStyle)
        .environment(\.toggleStyle, look.toggleStyle)
        .environment(\.gaugeStyle, look.gaugeStyle)
        .horizontalRadioGroupLayout()
        .controlStyle(look.controlStyle)
        .controlSize(look.size)
        .textCase(look.size == .large ? .uppercase : nil)
        // The recipe on the camera's last row but one.
        .frame(width: 70, height: 19, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Rail · Booking") }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 2) {
                GroupBox("Edinburgh → London King's Cross") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Sat 14 Nov · 09:30 → 13:52")
                        Text(verbatim: "4 h 22 m · direct · wifi and a café bar")
                            .foregroundStyle(.palette.foregroundSecondary)
                        Form {
                            Picker("Class", selection: $seatClass) {
                                Text("Standard").tag(0)
                                Text("First").tag(1)
                                Text("Sleeper").tag(2)
                            }
                            Stepper("Passengers", value: $passengers, in: 1...6)
                        }
                        .formStyle(.columns)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 48)
                GroupBox("Coach C") { busyness }
                    .frame(width: 20)
            }
            HStack(alignment: .top, spacing: 2) {
                GroupBox("Lead passenger") {
                    Form {
                        LabeledContent("Name") { TextField("Name", text: $name) }
                        LabeledContent("Email") { TextField("Email", text: $email) }
                        LabeledContent("Phone") { TextField("Phone", text: $phone) }
                    }
                    .formStyle(.columns)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 48)
                GroupBox("Extras") {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Window seat", isOn: $window)
                        Toggle("Quiet coach", isOn: $quiet)
                        Toggle("Bicycle", isOn: $bike)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 20)
            }
            HStack(spacing: 2) {
                Picker("Railcard", selection: $railcard) {
                    Text("None").tag(0)
                    Text("16–25").tag(1)
                    Text("Senior").tag(2)
                    Text("Two Together").tag(3)
                }
                .pickerStyle(.menu)
                Spacer()
                Text(verbatim: "£\(price)").bold()
                Button("Back") {}
                Button("Book seats") {}.buttonStyle(.borderedProminent)
            }
        }
    }

    /// How full the coach is with this booking: the gauge, and the count.
    private var busyness: some View {
        let seats = Self.taken + passengers
        return VStack(alignment: .leading, spacing: 0) {
            Gauge(value: Double(seats) / Double(Self.coachSeats)) {
                EmptyView()
            } currentValueLabel: {
                Text(verbatim: "\(seats * 100 / Self.coachSeats)%")
            }
            Text(verbatim: "\(seats) of \(Self.coachSeats) taken")
                .foregroundStyle(.palette.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 4, alignment: .topLeading)
    }
}
