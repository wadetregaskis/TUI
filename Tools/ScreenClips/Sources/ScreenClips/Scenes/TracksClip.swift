//  🖥️ TUI — A Terminal UI framework for Swift
//  TracksClip.swift
//
//  `tracks`: a backup in progress, its one bar restyled every couple of
//  seconds — from the plain fills to ones an app might wear for fun (hearts,
//  Pac-Man eating the dots ahead of it) — and its bandwidth slider with it,
//  each look named under the control by the `.trackStyle` that makes it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let tracksClip = Clip(
    id: "tracks",
    title: "Track styles",
    columns: 112,
    rows: 30,
    terminal: "iterm",
    output: 800,
    script: tracksScript(),
    run: { await TracksApp.main() }
)

/// A style every 1.6 s, the slider nudged in each, and back to the first.
private func tracksScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 60, height: 16)), .cue("style 0"), .wait(1.6)]
    for index in 1..<TrackLook.progressStyles.count {
        script += [.cue("style \(index)"), .wait(0.6)]
        script += Step.repeat(index.isMultiple(of: 2) ? .right : .left, 3, interval: 0.08)
        script += [.wait(0.76)]
    }
    script += [.cue("style 0"), .wait(1.2)]
    return script
}

/// The looks, as the caption names them.
enum TrackLook {
    static let progressStyles: [(name: String, style: TrackStyle)] = [
        (".blockFine", .blockFine),
        (".shadeRamp(gradient:)", .shadeRamp(gradient: Gradient(colors: [.rgb(40, 200, 190), .rgb(150, 90, 230)]))),
        (".braille", .braille),
        (".custom(▰ ▱)", .custom(TrackConfiguration(fullGlyph: "▰", background: .glyph("▱")))),
        (".custom(♥ ♡)", .custom(TrackConfiguration(
            fullGlyph: "♥", background: .glyph("♡"),
            fillGradient: Gradient(colors: [.rgb(255, 80, 120), .rgb(255, 160, 200)])))),
        (".threeSegment(\"Lo\", \"o\", \"ading\")", .threeSegment(leading: "Lo", middle: "o", trailing: "ading")),
        (".threeSegment(\" \", \" \", \"ᗧ\", \"• \")", .threeSegment(
            leading: " ", middle: " ", trailing: "ᗧ", backgroundPattern: "• ",
            coloring: .solid(.rgb(255, 220, 0)))),
    ]

    static let sliderStyles: [(name: String, style: TrackStyle)] = [
        (".knob", .knob), (".dot", .dot), (".bar", .bar), (".shade", .shade),
        (".threeSegment(\"\", \"━\", \"◆\", \"┄\")", .threeSegment(leading: "", middle: "━", trailing: "◆", backgroundPattern: "┄")),
        (".marker", .marker), (".knob", .knob),
    ]
}

struct TracksApp: App {
    var body: some Scene {
        WindowGroup("TUI · Backup") {
            BackupPage()
                .palette(SystemPalette(.green))
        }
    }
}

/// A backup to a NAS: what it is copying, how far it has got, how fast it may go.
struct BackupPage: View {
    @State private var style = 0
    /// When the copy (re)started: how far it has got is worked out from the
    /// time each frame is drawn, so the bars move a little every frame
    /// instead of jumping on a timer's tick.
    @State private var started = Date()
    @State private var limit = 60.0

    private let files = [
        "IMG_4021.HEIC", "IMG_4022.HEIC", "Laugavegur-day2.mov", "IMG_4025.HEIC",
        "Panorama-Landmannalaugar.jpg", "IMG_4031.HEIC", "IMG_4032.HEIC",
    ]

    /// GB copied at `date`: 18.4 to begin with, 1.8 GB a second, and
    /// stopping short of finishing. Fast enough that the bar's fill moves an
    /// eighth of a cell about every 55 ms: at a gigabyte a second it moved one
    /// every 100 ms, a step the eye reads as a judder.
    private func copied(at date: Date) -> Double {
        min(41.5, 18.4 + date.timeIntervalSince(started) * 1.8)
    }

    var body: some View {
        TimelineView(.animation) { context in
            page(copied: copied(at: context.date))
        }
        .task {
            for await cue in ClipCues.stream() {
                if cue.hasPrefix("style "), let index = Int(cue.dropFirst(6)) {
                    style = index
                    // The first style starts the copy again: the loop's seam.
                    if index == 0 { started = Date() }
                }
            }
        }
    }

    private func page(copied: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Backing up “Photos” to nas-01.local").bold()
                Text(verbatim: String(format: "%.1f of 42.0 GB · about %d minutes left", copied, Int((42 - copied) * 1.6)))
                    .foregroundStyle(.palette.foregroundSecondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ProgressView(value: copied, total: 42)
                    .trackStyle(TrackLook.progressStyles[style].style)
                    .frame(width: 52)
                Text(verbatim: TrackLook.progressStyles[style].name).foregroundStyle(.palette.foregroundTertiary)
            }
            VStack(alignment: .leading, spacing: 0) {
                LabeledContent("Bandwidth") {
                    Slider(value: $limit, in: 10...100, step: 5)
                        .trackStyle(TrackLook.sliderStyles[style].style)
                }
                .frame(width: 52)
                Text(verbatim: "\(Int(limit)) MB/s · \(TrackLook.sliderStyles[style].name)")
                    .foregroundStyle(.palette.foregroundTertiary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack(spacing: 1) {
                        Text(verbatim: index < 4 ? "✓" : "·")
                            .foregroundStyle(index < 4 ? .palette.success : .palette.foregroundTertiary)
                        Text(verbatim: file)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 2)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Backup") }
        }
    }
}
