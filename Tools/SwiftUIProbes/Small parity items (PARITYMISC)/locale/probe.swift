import SwiftUI
import AppKit

@MainActor func png<V: View>(_ v: V) -> Data {
    let r = ImageRenderer(content: v.padding(2).background(Color.white))
    r.scale = 2
    guard let cg = r.cgImage else { return Data() }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) ?? Data()
}
@MainActor func which<V: View>(_ name: String, _ v: V, _ candidates: [String]) {
    let got = png(v)
    let match = candidates.first { png(Text(verbatim: $0)) == got } ?? "none of \(candidates)"
    print(name.padding(toLength: 56, withPad: " ", startingAt: 0), "->", match)
}

MainActor.assumeIsolated {
    print("Bundle.main:", Bundle.main.bundlePath, "preferred:", Bundle.main.preferredLocalizations, "Locale.current:", Locale.current.identifier)
    let c = ["Hello", "Hallo", "Bonjour", "greeting", "English only", "only.en"]
    which("default", Text("greeting"), c)
    which("env locale de", Text("greeting").environment(\.locale, Locale(identifier: "de")), c)
    which("env locale de_CH", Text("greeting").environment(\.locale, Locale(identifier: "de_CH")), c)
    which("env locale fr_FR", Text("greeting").environment(\.locale, Locale(identifier: "fr_FR")), c)
    which("env locale pt_BR (no pt.lproj)", Text("greeting").environment(\.locale, Locale(identifier: "pt_BR")), c)
    which("env locale ja (no ja.lproj)", Text("greeting").environment(\.locale, Locale(identifier: "ja")), c)
    which("env de, key only in en", Text("only.en").environment(\.locale, Locale(identifier: "de")), c)
    which("env de, outer VStack", VStack { Text("greeting") }.environment(\.locale, Locale(identifier: "de")), c)
    // A Button title key
    which("Button in env de (label text)", Text("greeting").environment(\.locale, Locale(identifier: "de")), c)
    // interpolated number formatting by env locale
    let n = 1234.5
    which("interp number default", Text("\(n)"), ["1234.5", "1,234.5", "1.234,5", "1234,5", "1 234,5", "1’234.5"])
    which("interp number env de", Text("\(n)").environment(\.locale, Locale(identifier: "de")), ["1234.5", "1,234.5", "1.234,5", "1234,5"])
    which("format number env de", Text(n, format: .number).environment(\.locale, Locale(identifier: "de")), ["1234.5", "1,234.5", "1.234,5", "1234,5"])
}
