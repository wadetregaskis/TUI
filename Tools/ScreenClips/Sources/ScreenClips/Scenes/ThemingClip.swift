//  🖥️ TUI — A Terminal UI framework for Swift
//  ThemingClip.swift
//
//  `theming`: one small app, its look changed under it — the palette walked
//  through phosphor greens and ambers, Terminal.app's profiles, light pages
//  and dark, and the border appearance with it — while it is in use.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let themingClip = Clip(
    id: "theming",
    title: "Theming",
    columns: 112,
    rows: 30,
    script: [
        // On the build's panels, the target list's edge at the left.
        .camera(Shot(x: 16.4, y: 3, width: 56, height: 16)),
        .wait(0.8), .down, .wait(0.2), .space,
        .wait(0.4), .cue("palette Amber"),
        .wait(0.9), .cue("palette Ocean"), .cue("appearance doubleLine"),
        .wait(0.4), .down, .wait(0.2), .space,
        .wait(0.4), .cue("palette Novel"),
        .wait(0.9), .cue("palette Violet"), .cue("appearance heavy"),
        .wait(0.4), .down, .wait(0.2), .space,
        .wait(0.4), .cue("palette Silver Aerogel"),
        .wait(0.9), .cue("palette Red Sands"), .cue("appearance line"),
        .wait(0.4), .up, .wait(0.2), .up, .wait(0.2), .up, .wait(0.2), .space,
        // Back where it began, so the loop has no seam.
        .wait(0.3), .cue("palette Green"), .cue("appearance rounded"),
        .wait(0.6),
    ],
    run: { await ThemingApp.main() }
)

/// The look the cues change: a palette, by name, and a border appearance.
struct ThemingLook {
    var palette: any Palette = SystemPalette(.green)
    var appearance: Appearance = .rounded

    mutating func apply(_ cue: String) {
        let parts = cue.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "palette":
            if let palette = PaletteRegistry.palette(withName: parts[1]) { self.palette = palette }
        case "appearance":
            switch parts[1] {
            case "line": appearance = .line
            case "doubleLine": appearance = .doubleLine
            case "heavy": appearance = .heavy
            default: appearance = .rounded
            }
        default: break
        }
    }
}

struct ThemingApp: App {
    @State private var look = ThemingLook()

    var body: some Scene {
        WindowGroup("TUI · Theming") {
            ThemingPage(paletteName: look.palette.name)
                .task {
                    for await cue in ClipCues.stream() { look.apply(cue) }
                }
        }
        .palette(look.palette)
        .appearance(look.appearance)
    }
}

/// A build dashboard: targets down the side, the selected one's build beside
/// them — enough kinds of control that every palette role shows.
struct ThemingPage: View {
    let paletteName: String
    @State private var selection: String? = "TUI"
    @State private var optimise = true
    @State private var strip = false
    @State private var jobs = 8.0
    /// The build's clock: the bar creeps on between selections.
    @State private var tick = 0

    private let targets = ["TUI", "TUIApp", "TUILists", "TUITables", "Example", "Stress"]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            List(selection: $selection) {
                ForEach(targets, id: \.self) { target in
                    Label(target, systemImage: "shippingbox")
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                GroupBox("Building \(selection ?? "—")") {
                    VStack(alignment: .leading, spacing: 0) {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))% · \(Int(progress * 1_840)) of 1,840 files")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                }
                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Optimise for speed", isOn: $optimise)
                        Toggle("Strip symbols", isOn: $strip)
                        LabeledContent("Jobs") { Slider(value: $jobs, in: 1...16) }
                    }
                }
                HStack(spacing: 2) {
                    Text("✓ 1,208 passed").foregroundStyle(.palette.success)
                    Text("⚠ 3 warnings").foregroundStyle(.palette.warning)
                    Text("✗ 0 failed").foregroundStyle(.palette.error)
                }
                HStack(spacing: 2) {
                    Button("Clean") {}
                    Button("Build") {}.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Theming · \(paletteName)") }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                tick += 1
            }
        }
    }

    /// Each target is a different way through its build, so moving the
    /// selection moves the bar.
    private var progress: Double {
        let index = targets.firstIndex(of: selection ?? "") ?? 0
        let base = [0.42, 0.25, 0.58, 0.37, 0.54, 0.21][index]
        return min(1, base + Double(tick % 40) * 0.01)
    }
}
