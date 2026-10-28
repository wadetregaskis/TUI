//  🖥️ TUI — A Terminal UI framework for Swift
//  TracksClip.swift
//
//  `tracks`: a backup in progress, its one bar filling while it is restyled
//  every couple of seconds — from the plain fills to ones an app might wear
//  for fun (hearts, a gradient "Looooading", Pac-Man eating the dots ahead of
//  it) — each look named under the control by the `.trackStyle` that makes
//  it. Its files are ticked off as it passes them, a spinner of the look's
//  own beside each one still to come; and once the pointer comes in and
//  drags the bandwidth limit from 40 MB/s to 70, and the copy speeds up.
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
    script: tracksTiming.steps,
    run: { await TracksApp.main() }
)

/// Where the slider's track is: row 10, its arrows ◀ in column 13 and ▶ in
/// 49 (1-based, read from the page drawn headless at 112 × 30; the track
/// styles change its glyphs, never where they are), so its knob sits a third
/// of the way along (40 MB/s of 10–100) in column 25, and two thirds (70) in
/// 37.
private enum SliderTrack {
    static let row = 10
    static let third = 25
    static let twoThirds = 37
}

/// How long each look shows.
private let lookSeconds = 1.8

/// The copy runs from start to end, a look every 1.8 s. Once, a few looks in,
/// the pointer comes in, drags the bandwidth limit from a third of the way to
/// two thirds, and goes — and the copy visibly speeds up. Nothing jumps but
/// the loop's seam, where the copy starts again.
private func tracksScript() -> (steps: [Step], adjustedAt: Double) {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 60, height: 17)), .cue("start"), .cue("style 0")]
    script += [.wait(lookSeconds)]
    var adjustedAt = 0.0
    for index in 1..<TrackLook.progressStyles.count {
        script += [.cue("style \(index)")]
        guard index == 2 else {
            script += [.wait(lookSeconds)]
            continue
        }
        let knob = { (column: Int) in (column, SliderTrack.row) }
        script += [.wait(0.2)]
        script += Step.glide(from: (64, 17), to: knob(SliderTrack.third), over: 0.5)
        script += Step.drag(from: knob(SliderTrack.third), to: knob(SliderTrack.twoThirds), interval: 0.05)
        adjustedAt = seconds(of: script)
        script += Step.glide(from: knob(SliderTrack.twoThirds), to: (64, 18), over: 0.5)
    }
    return (script, adjustedAt)
}

/// The seconds `steps` take: their waits.
private func seconds(of steps: [Step]) -> Double {
    steps.reduce(0.0) { total, step in
        if case .wait(let seconds) = step { total + seconds } else { total }
    }
}

private let tracksTiming = tracksScript()

/// The script's length, for the copy's rate: so it fills over the whole clip.
private let tracksSeconds = seconds(of: tracksTiming.steps)

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
        (".threeSegment(\"Lo\", \"o\", \"ading\", coloring: .gradient)", .threeSegment(
            leading: "Lo", middle: "o", trailing: "ading",
            coloring: .gradient(Gradient(colors: [.rgb(255, 120, 60), .rgb(255, 210, 80), .rgb(120, 220, 140)])))),
        (".threeSegment(\" \", \" \", \"ᗧ\", \"• \")", .threeSegment(
            leading: " ", middle: " ", trailing: "ᗧ", backgroundPattern: "• ",
            coloring: .solid(.rgb(255, 220, 0)))),
    ]

    /// The spinner on each file not yet copied, one per look: each a cell
    /// wide, so the names beside them stay put.
    static let spinnerStyles: [SpinnerStyle] = [.dots, .line, .pie, .blockWedge, .box, .spinningTriangle, .shade]

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
    @State private var limit = 40.0

    private let files = [
        "IMG_4021.HEIC", "IMG_4022.HEIC", "Laugavegur-day2.mov", "IMG_4025.HEIC",
        "Panorama-Landmannalaugar.jpg", "IMG_4031.HEIC", "IMG_4032.HEIC",
    ]

    /// Where the copy had got to when the limit last changed, and when: the
    /// copy runs at the limit's pace from there.
    @State private var checkpoint = (date: Date(), copied: 3.0)

    /// GB copied a second for each MB/s of limit: so the copy goes from 3 GB to
    /// 40 over the clip, at 40 MB/s until the pointer raises the limit and at
    /// 70 after (a clip's fiction: about two gigabytes a second, which moves
    /// the fill an eighth of a cell every 50 ms or so, smooth where a gigabyte
    /// a second judders).
    private static let rate = 37 / (40 * tracksTiming.adjustedAt + 70 * (tracksSeconds - tracksTiming.adjustedAt))

    /// GB copied at `date`, at `limit`'s pace since the last checkpoint.
    private func copied(at date: Date, limit: Double) -> Double {
        min(40, checkpoint.copied + date.timeIntervalSince(checkpoint.date) * limit * Self.rate)
    }

    var body: some View {
        TimelineView(.animation) { context in
            page(copied: copied(at: context.date, limit: limit))
        }
        .onChange(of: limit) { old, _ in
            let now = Date()
            checkpoint = (now, copied(at: now, limit: old))
        }
        .task {
            for await cue in ClipCues.stream() {
                // The copy starts again at the clip's start, and only there: the
                // loop's seam.
                if cue == "start" {
                    limit = 40
                    checkpoint = (Date(), 3)
                }
                if cue.hasPrefix("style "), let index = Int(cue.dropFirst(6)) { style = index }
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
                // A file is ticked off as the copy passes it; until then a
                // spinner turns beside it, the one being copied brighter.
                let done = Int((copied - 3) / 37 * Double(files.count))
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack(spacing: 1) {
                        if index < done {
                            Text(verbatim: "✓").foregroundStyle(.palette.success)
                        } else {
                            Spinner(
                                style: TrackLook.spinnerStyles[style],
                                color: index == done ? .palette.accent : .palette.foregroundTertiary)
                        }
                        Text(verbatim: file)
                            .foregroundStyle(index > done ? .palette.foregroundSecondary : .palette.foreground)
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
