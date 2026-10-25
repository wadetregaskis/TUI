//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StylesClip.swift
//
//  `styles`: one booking form, restyled under the person using it — the
//  controls' chrome (filled, lines, Braille dots, none), the border
//  appearance, switches or checkboxes, control size, and type: bold,
//  uppercase titles — each look named on the form's last line by the
//  modifiers that make it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

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

/// A look every two seconds or so, with a key pressed in each so the form is
/// seen in use, and back to the first.
private func stylesScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 58, height: 20)), .wait(1.2)]
    for look in StyleLook.allCases.dropFirst() {
        script += [.cue("look \(look.rawValue)"), .wait(0.9), .tab, .wait(0.5), .space, .wait(0.9)]
    }
    script += [.cue("look \(StyleLook.allCases[0].rawValue)"), .wait(1.0)]
    return script
}

/// The looks the clip walks, each a handful of modifiers.
enum StyleLook: String, CaseIterable {
    case filled, lines, braille, poster, minimal

    var controlStyle: ControlStyle {
        switch self {
        case .filled, .poster: .block
        case .lines: .lines
        case .braille: .braille(thickness: 2)
        case .minimal: .blank
        }
    }

    var appearance: Appearance {
        switch self {
        case .filled: .rounded
        case .lines: .heavy
        case .braille: .braille
        case .poster: .doubleLine
        case .minimal: .line
        }
    }

    var switches: Bool { self == .filled || self == .poster || self == .braille }
    var size: ControlSize { self == .poster ? .large : .regular }
    var shouts: Bool { self == .poster }

    /// What the form's last line says the look is made of.
    var recipe: String {
        switch self {
        case .filled: ".controlStyle(.block)  .appearance(.rounded)"
        case .lines: ".controlStyle(.lines)  .appearance(.heavy)  .toggleStyle(.checkbox)"
        case .braille: ".controlStyle(.braille(thickness: 2))  .appearance(.braille)"
        case .poster: ".controlSize(.large)  .textCase(.uppercase)  .bold()"
        case .minimal: ".controlStyle(.blank)  .appearance(.line)"
        }
    }

    var palette: any Palette {
        switch self {
        case .filled: SystemPalette(.white)
        case .lines: AppleTerminalPalette(.homebrew)
        case .braille: AppleTerminalPalette(.basic)
        case .poster: SystemPalette(.red)
        case .minimal: AppleTerminalPalette(.solidColors)
        }
    }
}

struct StylesApp: App {
    @State private var look = StyleLook.filled

    var body: some Scene {
        WindowGroup("TUIkit · Styles") {
            BookingForm(look: look)
                .task {
                    for await cue in ClipCues.stream() {
                        if cue.hasPrefix("look "), let next = StyleLook(rawValue: String(cue.dropFirst(5))) {
                            look = next
                        }
                    }
                }
        }
        .palette(look.palette)
        .appearance(look.appearance)
    }
}

/// A train booking: route, class, extras, and the two buttons.
struct BookingForm: View {
    let look: StyleLook
    @State private var seatClass = 1
    @State private var window = true
    @State private var quiet = false
    @State private var bike = false
    @State private var passengers = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            GroupBox("Edinburgh → London King's Cross") {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Sat 14 Nov · 09:30 → 13:52 · 4 h 22 m · direct")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Picker("Class", selection: $seatClass) {
                        Text("Standard").tag(0)
                        Text("First").tag(1)
                        Text("Sleeper").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Passengers: \(passengers)", value: $passengers, in: 1...6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Extras") {
                VStack(alignment: .leading, spacing: 0) {
                    toggle("Window seat", isOn: $window)
                    toggle("Quiet coach", isOn: $quiet)
                    toggle("Bicycle space", isOn: $bike)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 2) {
                Text(verbatim: "£\(passengers * [54, 129, 210][seatClass])").bold()
                Spacer()
                Button("Back") {}
                Button("Book seats") {}.buttonStyle(.borderedProminent)
            }
            Text(verbatim: look.recipe)
                .textCase(nil)
                .bold(false)
                .foregroundStyle(.palette.foregroundTertiary)
        }
        .controlStyle(look.controlStyle)
        .controlSize(look.size)
        .textCase(look.shouts ? .uppercase : nil)
        .bold(look.shouts)
        .frame(width: 56, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Rail · Booking") }
        }
    }

    @ViewBuilder private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        if look.switches {
            Toggle(label, isOn: isOn).toggleStyle(.switch)
        } else {
            Toggle(label, isOn: isOn).toggleStyle(.checkbox)
        }
    }
}
