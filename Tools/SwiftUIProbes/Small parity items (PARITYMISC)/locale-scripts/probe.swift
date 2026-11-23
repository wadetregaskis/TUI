// H-54 (2026-11-23): does a subtree's `\.locale` pick a script or a region's
// table, as it picks a language's (`../locale/probe.swift`, 2026-10-18)? And
// does `Text(LocalizedStringResource)` follow `\.locale` as `Text("key")` does?
//
// Run as an app bundle, so `Bundle.main` holds the `.lproj` folders: see
// `run.sh` beside this file. What it printed is `probe.out`.
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
    print(name.padding(toLength: 48, withPad: " ", startingAt: 0), "->", match)
}

MainActor.assumeIsolated {
    print("localizations:", Bundle.main.localizations.sorted(), "preferred:", Bundle.main.preferredLocalizations)
    let c = [
        "Hello", "Hallo", "Hello-Hans", "Hello-Hant", "Ola-pt", "Ola-BR", "Ola-PT", "greeting",
        "Only-Hans", "only.hans", "Only-pt", "only.pt", "English only", "only.en",
    ]
    func under(_ id: String, _ key: LocalizedStringKey = "greeting") -> some View {
        Text(key).environment(\.locale, Locale(identifier: id))
    }
    which("default", Text("greeting"), c)
    for id in ["zh-Hant", "zh_TW", "zh-Hant-TW", "zh_HK", "zh-Hans", "zh", "zh_CN", "zh-Hans-SG"] {
        which("env locale \(id)", under(id), c)
    }
    for id in ["pt-BR", "pt_BR", "pt-PT", "pt_PT", "pt", "pt_AO", "pt_MZ"] {
        which("env locale \(id)", under(id), c)
    }
    which("env zh-Hant, key only in zh-Hans", under("zh-Hant", "only.hans"), c)
    which("env zh_TW, key only in zh-Hans", under("zh_TW", "only.hans"), c)
    which("env pt-BR, key only in pt", under("pt-BR", "only.pt"), c)
    which("env pt_AO, key only in pt", under("pt_AO", "only.pt"), c)
    which("env zh-Hant, key only in en", under("zh-Hant", "only.en"), c)
    // FENV-16: a LocalizedStringResource, SwiftUI's nearest to TUI's `Text(localized:)`.
    which("resource, default", Text(LocalizedStringResource("greeting")), c)
    which("resource, env locale de", Text(LocalizedStringResource("greeting")).environment(\.locale, Locale(identifier: "de")), c)
    which("resource, env locale zh-Hant", Text(LocalizedStringResource("greeting")).environment(\.locale, Locale(identifier: "zh-Hant")), c)
    which("String(localized:), env locale de", Text(String(localized: "greeting")).environment(\.locale, Locale(identifier: "de")), c)
    // Whether a resource's Markdown is drawn, as a key's is: `bold` is "**Bold** text" in en.lproj.
    let styled = png(Text("**Bold** text" as LocalizedStringKey))
    let plain = png(Text(verbatim: "**Bold** text"))
    let resource = png(Text(LocalizedStringResource("bold")))
    print("resource with Markdown".padding(toLength: 48, withPad: " ", startingAt: 0), "->",
          resource == styled ? "drawn as Markdown" : resource == plain ? "drawn as written" : "neither")
}
