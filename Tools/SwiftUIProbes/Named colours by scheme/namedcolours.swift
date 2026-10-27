// What SwiftUI's named colours resolve to under each colour scheme, and what
// a colour resolved in a bare environment (as a view body sees one) answers.
//
// Cited by Sources/TUIStyling/Color/SystemColor.swift and
// Documentation/Historical/Colour and styling/Named colours, asset catalogues
// and dark values.md. Top-level code: build it alone.
import AppKit
import SwiftUI

let names: [(String, Color)] = [
    ("black", .black), ("white", .white), ("red", .red), ("orange", .orange), ("yellow", .yellow),
    ("green", .green), ("mint", .mint), ("teal", .teal), ("cyan", .cyan), ("blue", .blue),
    ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("brown", .brown), ("gray", .gray),
]

func hex(_ resolved: Color.Resolved) -> String {
    func byte(_ component: Float) -> String {
        String(format: "%02X", Int((min(1, max(0, component)) * 255).rounded()))
    }
    return "#" + byte(resolved.red) + byte(resolved.green) + byte(resolved.blue)
}

var light = EnvironmentValues()
light.colorScheme = .light
var dark = EnvironmentValues()
dark.colorScheme = .dark
let bare = EnvironmentValues()

print("name     bare     light    dark")
for (name, colour) in names {
    let row = [hex(colour.resolve(in: bare)), hex(colour.resolve(in: light)), hex(colour.resolve(in: dark))]
    print(name.padding(toLength: 8, withPad: " ", startingAt: 0), row.joined(separator: " "))
}

// The same hues through AppKit, under each appearance, converted to sRGB: the
// cross-check that SwiftUI's names are the system palette.
let system: [(String, NSColor)] = [
    ("red", .systemRed), ("orange", .systemOrange), ("yellow", .systemYellow), ("green", .systemGreen),
    ("mint", .systemMint), ("teal", .systemTeal), ("cyan", .systemCyan), ("blue", .systemBlue),
    ("indigo", .systemIndigo), ("purple", .systemPurple), ("pink", .systemPink), ("brown", .systemBrown),
    ("gray", .systemGray),
]
func hex(_ colour: NSColor) -> String {
    guard let srgb = colour.usingColorSpace(.sRGB) else { return "-------" }
    func byte(_ component: CGFloat) -> String { String(format: "%02X", Int((component * 255).rounded())) }
    return "#" + byte(srgb.redComponent) + byte(srgb.greenComponent) + byte(srgb.blueComponent)
}
print("")
print("NSColor  aqua     darkAqua")
for (name, colour) in system {
    var aqua = "", darkAqua = ""
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { aqua = hex(colour) }
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { darkAqua = hex(colour) }
    print(name.padding(toLength: 8, withPad: " ", startingAt: 0), aqua, darkAqua)
}
