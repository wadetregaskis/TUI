//  🖥️ TUI — A Terminal UI framework for Swift
//  MixerClip.swift
//
//  `mixer`: a mixing desk in the middle of a session, playing. The playhead
//  crosses the arrangement, every channel's meters bounce to the beat (an LED
//  ladder lit green to amber to red, its peak held a moment), the spectrum
//  analyser dances, and the main out's ladders and loudness follow — while the
//  pointer pushes the bass into the red until the clip lights flash, mutes the
//  hats, pans the keys, solos the vocal, and puts everything back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let mixerClip = Clip(
    id: "mixer",
    title: "Mixer",
    columns: 112,
    rows: 34,
    output: 800,
    // Every meter on the desk moves ten times a second, so nearly every
    // picture is a new one: the nine seconds come to about 760 KB at quality
    // 55, and no quality reaches the default 450 KB — stepping down towards it
    // only smears the small text. As the photographic clips are, it is allowed
    // more.
    budgetKB: 800,
    script: mixerScript(),
    run: { await MixerApp.main() }
)

/// Where the pointer acts: 1-based cells, read from the desk drawn at 112 × 34.
/// A slider's value is its knob's cell along the track (the fader's 14 cells
/// from column 27, the pan's 9), so a drag that ends where it began puts the
/// value back exactly.
private enum Spot {
    static let voxSolo = (23, 28)
    static let hatsMute = (19, 22)
    static let bassFader = (35, 24)
    static let bassFaderTop = (40, 24)
    static let keysPan = (31, 27)
    static let keysPanLeft = (27, 27)
}

/// One pass of the loop — six bars at 160 BPM, nine seconds — with the
/// pointer working the desk: the bass pushed into the red until the clip
/// lights flash and pulled back, the hats muted, the keys panned hard left and
/// home, the hats back in, and the vocal soloed and back. Every change is
/// undone by the loop's end, where the pointer rests on the vocal's solo,
/// focused and under the pointer, as at the start.
private func mixerScript() -> [Step] {
    var script: [Step] = [
        .camera(Shot(x: 1, y: 0, width: 108, height: 31)),
        // The pointer over the vocal's solo, as the last click leaves it: a
        // move with no button (35), so the app knows where the pointer is.
        Step.mouse(35, Spot.voxSolo.0, Spot.voxSolo.1), .wait(0.3),
    ]
    script += Step.glide(from: Spot.voxSolo, to: Spot.bassFader, over: 0.35)
    script += Step.drag(from: Spot.bassFader, to: Spot.bassFaderTop, interval: 0.1) + [.wait(1.0)]
    script += Step.drag(from: Spot.bassFaderTop, to: Spot.bassFader, interval: 0.08)
    script += Step.glide(from: Spot.bassFader, to: Spot.hatsMute, over: 0.35)
    script += Step.click(Spot.hatsMute.0, Spot.hatsMute.1) + [.wait(0.3)]
    script += Step.glide(from: Spot.hatsMute, to: Spot.keysPan, over: 0.3)
    script += Step.drag(from: Spot.keysPan, to: Spot.keysPanLeft, interval: 0.08) + [.wait(0.35)]
    script += Step.drag(from: Spot.keysPanLeft, to: Spot.keysPan, interval: 0.08)
    script += Step.glide(from: Spot.keysPan, to: Spot.hatsMute, over: 0.3)
    script += Step.click(Spot.hatsMute.0, Spot.hatsMute.1) + [.wait(0.25)]
    script += Step.glide(from: Spot.hatsMute, to: Spot.voxSolo, over: 0.35)
    script += Step.click(Spot.voxSolo.0, Spot.voxSolo.1) + [.wait(1.3)]
    script += Step.click(Spot.voxSolo.0, Spot.voxSolo.1)
    // To the loop's end, where the playhead wraps to where it started.
    let played = script.reduce(0.0) { total, step in
        if case .wait(let seconds) = step { total + seconds } else { total }
    }
    script += [.wait(max(0.05, Session.loopSeconds - played)), .cue("reset")]
    return script
}

struct MixerApp: App {
    var body: some Scene {
        WindowGroup("TUI · Tideline") {
            MixingDesk()
                .palette(AppleTerminalPalette(.pro))
        }
    }
}

/// The desk: the arrangement and the spectrum on top, the channel strips and
/// the main out below, all drawn from where the playhead is.
struct MixingDesk: View {
    @State private var mix = MixState.start
    /// Where the playhead's clock starts: it, and so every meter, is worked out
    /// from the time each frame is drawn. Never reset: everything drawn from it
    /// repeats every nine seconds, the script's length, so the clip's last
    /// frame is its first wherever in the loop the script happens to start —
    /// and a cue to restart it would arrive a little late (the cue is read
    /// between frames), its jump filmed.
    @State private var started = Date()
    @State private var view = "Mix"
    /// Which channel's solo holds the focus: the vocal's, to begin with,
    /// where the script's last click leaves it, so the loop has no seam.
    @FocusState private var soloFocus: Int?

    var body: some View {
        // Ten pictures a second, as a desk's meters refresh: every frame of the
        // film between them is the same picture, which the encoder keeps as
        // one. Every meter moves at once, so each picture costs nearly a whole
        // frame of the clip: sixteen seconds at thirty a second came to
        // 1.3 MB, twelve seconds at ten 900 KB.
        TimelineView(.animation(minimumInterval: 1.0 / 10)) { context in
            page(time: (context.date.timeIntervalSince(started) * 10).rounded(.down) / 10)
        }
        .task {
            // Every change the script makes it also undoes; this only makes
            // sure of it, after the clip's last frame.
            for await cue in ClipCues.stream() where cue == "reset" {
                mix = .start
            }
        }
    }

    private func page(time: Double) -> some View {
        let loopTime = Signal.wrapped(time)
        let playhead = min(Session.loopCells - 1, Int(loopTime / Session.loopSeconds * Double(Session.loopCells)))
        return VStack(alignment: .leading, spacing: 0) {
            transport(time: loopTime)
            HStack(alignment: .top, spacing: 1) {
                arrangement(playhead: playhead)
                spectrum(time: time)
                    .frame(width: 33)
            }
            HStack(alignment: .top, spacing: 1) {
                strips(time: time)
                    .frame(width: 74)
                mainSection(time: time)
                    .frame(width: 33)
            }
            statusLine(time: loopTime)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .defaultFocus($soloFocus, Session.channels.count - 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "◆ Tideline — Night Drive") }
        }
    }

    // MARK: - Transport

    private func transport(time: Double) -> some View {
        let beats = time * Session.beatsPerSecond
        let bar = Session.firstBar + Int(beats) / 4
        let beat = Int(beats) % 4 + 1
        let sixteenth = Int(beats * 4) % 4 + 1
        let clock = 64 + time
        return HStack(spacing: 2) {
            Text(verbatim: " ◀◀  ▶  ■  ● ").foregroundStyle(Color.rgb(60, 230, 120)).bold()
            Text(verbatim: String(format: "%03d.%d.%d", bar, beat, sixteenth))
                .foregroundStyle(Color.rgb(255, 210, 90)).bold()
            Text(verbatim: String(format: "%02d:%05.2f", Int(clock) / 60, clock.truncatingRemainder(dividingBy: 60)))
                .foregroundStyle(Color.rgb(140, 220, 255))
            Text(verbatim: "160 BPM  4/4  ↻ 17–23")
                .foregroundStyle(.palette.foregroundSecondary)
            HStack(spacing: 1) {
                Text(verbatim: "CPU")
                ProgressView(value: 0.34 + 0.08 * Signal.osc(3, time) + 0.03 * Signal.osc(40, time))
                    .trackStyle(.blockFine)
                    .tint(Color.rgb(90, 200, 255))
                    .frame(width: 10)
            }
            Picker("View", selection: $view) {
                ForEach(["Edit", "Mix", "Main"], id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Arrangement and spectrum

    private func arrangement(playhead: Int) -> some View {
        GroupBox("Arrangement") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(verbatim: "      ")
                    Text(Arrangement.ruler(playhead: playhead))
                }
                ForEach(Session.channels.indices, id: \.self) { channel in
                    HStack(spacing: 0) {
                        Text(verbatim: "▌").foregroundStyle(Session.channels[channel].colour)
                        Text(verbatim: Session.channels[channel].name.padding(toLength: 5, withPad: " ", startingAt: 0))
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(Arrangement.lane(channel, playhead: playhead, audible: mix.audible(channel)))
                    }
                }
            }
        }
    }

    private func spectrum(time: Double) -> some View {
        GroupBox("Spectrum") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Spectrum.lines(mix, at: time).enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
                Text(verbatim: "40  100   400  1k   4k  16k")
                    .foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    // MARK: - Channel strips

    private func strips(time: Double) -> some View {
        GroupBox("Mixer") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Session.channels.indices, id: \.self) { channel in
                    strip(channel, time: time)
                }
            }
            .sliderShowsValue(false)
            .controlSize(.small)
        }
    }

    private func strip(_ channel: Int, time: Double) -> some View {
        let info = Session.channels[channel]
        let audible = mix.audible(channel)
        let level = (
            left: MixState.ballistic(at: time) { mix.level(channel, at: $0).left },
            right: MixState.ballistic(at: time) { mix.level(channel, at: $0).right })
        let peak = (
            left: MixState.held(at: time) { mix.level(channel, at: $0).left },
            right: MixState.held(at: time) { mix.level(channel, at: $0).right })
        return HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "▌" + info.name).foregroundStyle(audible ? info.colour : Color.rgb(110, 110, 116)).bold()
                Text(verbatim: " " + info.inserts).foregroundStyle(.palette.foregroundTertiary)
            }
            .frame(width: 13, alignment: .leading)
            HStack(spacing: 1) {
                Toggle("M", isOn: binding(channel, \.muted))
                    .tint(Color.rgb(255, 190, 40))
                Toggle("S", isOn: binding(channel, \.soloed))
                    .tint(Color.rgb(80, 200, 255))
                    .focused($soloFocus, equals: channel)
            }
            .toggleStyle(.button)
            VStack(alignment: .leading, spacing: 0) {
                Slider(value: $mix.faders[channel])
                    .tint(info.colour)
                    .frame(width: 16)
                Slider(value: $mix.pans[channel], in: -1...1)
                    .trackStyle(.marker)
                    .frame(width: 11)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: MixState.decibels(mix.faders[channel]))
                Text(verbatim: MixState.panText(mix.pans[channel])).foregroundStyle(.palette.foregroundSecondary)
            }
            .frame(width: 8, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                meter(level.left, peak: peak.left)
                meter(level.right, peak: peak.right)
            }
        }
    }

    /// A bound toggle for a channel's membership of one of the desk's sets.
    private func binding(_ channel: Int, _ set: WritableKeyPath<MixState, Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { mix[keyPath: set].contains(channel) },
            set: { isOn in
                if isOn { mix[keyPath: set].insert(channel) } else { mix[keyPath: set].remove(channel) }
            })
    }

    /// A channel meter: an LED ladder on its side, its peak held, and a clip light.
    private func meter(_ level: Double, peak: Double) -> some View {
        let width = 21
        let peakCell = min(width - 1, Int(min(1, peak) * Double(width)))
        return HStack(spacing: 1) {
            ProgressView(value: min(1, level))
                .trackStyle(.custom(TrackConfiguration(
                    fullGlyph: "▮", background: .glyph("▮"),
                    fillGradient: Gradient(stops: Session.meterStops),
                    backgroundGradient: Gradient(stops: Session.unlitStops))))
                .frame(width: width)
                .overlay(alignment: .leading) {
                    if peak > 0.04 {
                        Text(verbatim: "▮").foregroundStyle(Session.meterColour(Double(peakCell) / Double(width - 1)))
                            .offset(x: peakCell)
                    }
                }
            Text(verbatim: "●").foregroundStyle(peak > 1 ? Color.rgb(255, 50, 40) : Color.rgb(60, 30, 30))
        }
    }

    // MARK: - Master

    private func mainSection(time: Double) -> some View {
        let level = (
            left: MixState.ballistic(at: time) { mix.mainBus(at: $0).left },
            right: MixState.ballistic(at: time) { mix.mainBus(at: $0).right })
        let peak = (
            left: MixState.held(at: time) { mix.mainBus(at: $0).left },
            right: MixState.held(at: time) { mix.mainBus(at: $0).right })
        let clipping = max(peak.left, peak.right) > 1
        // Loudness is an average, so it moves slowly: the last 0.6 s of the bus.
        let recent = (0..<12).map { step in mix.mainBus(at: time - Double(step) / 20) }
        let loudness = max(0, min(1, recent.reduce(0) { $0 + $1.left + $1.right } / Double(recent.count) / 1.9))
        let reduction = max(0.08, min(1, 0.1 + (max(level.left, level.right) - 0.6) * 1.6))
        return GroupBox("Main Out") {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(MainLadder.lines(level: level, peak: peak).enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        Text(verbatim: " CLIP ").bold()
                            .foregroundStyle(clipping ? Color.rgb(255, 255, 255) : Color.rgb(120, 64, 64))
                            .background(clipping ? Color.rgb(220, 30, 30) : Color.rgb(54, 26, 26))
                        Text(verbatim: "−0.3 ceil").foregroundStyle(.palette.foregroundTertiary)
                    }
                    Text(verbatim: "L \(readout(peak.left))  R \(readout(peak.right))")
                        .foregroundStyle(.palette.foregroundSecondary)
                        .padding(.bottom, 1)
                    HStack(alignment: .top, spacing: 1) {
                        Gauge(value: loudness) {
                            Text(verbatim: "LUFS")
                        } currentValueLabel: {
                            Text(verbatim: String(format: "%.0f", -18 + 10 * loudness).replacingOccurrences(of: "-", with: "−"))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(Color.rgb(255, 190, 60))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "Loudness")
                            Text(verbatim: "LRA 6.2").foregroundStyle(.palette.foregroundTertiary)
                            Text(verbatim: "TP  −1.1").foregroundStyle(.palette.foregroundTertiary)
                        }
                    }
                    Gauge(value: 0.55 + 0.25 * Signal.osc(5, time), in: -1...1) {
                        Text(verbatim: "Phase")
                    }
                    .gaugeStyle(.accessoryLinear)
                    .frame(width: 15)
                    Text(verbatim: "Limiter")
                    ProgressView(value: reduction)
                        .trackStyle(.blockFine)
                        .tint(Color.rgb(255, 120, 60))
                        .frame(width: 15)
                    Slider(value: $mix.output)
                        .sliderShowsValue(false)
                        .controlSize(.small)
                        .tint(Color.rgb(230, 230, 240))
                        .frame(width: 15)
                }
            }
        }
    }

    /// A level in dBFS, as a peak readout shows it.
    private func readout(_ level: Double) -> String {
        let value = level > 0.001 ? max(-60, 20 * log10(level)) : -60
        return String(format: "%5.1f", value).replacingOccurrences(of: "-", with: "−")
    }

    private func statusLine(time: Double) -> some View {
        Text(verbatim: " 48 kHz · 24-bit · buffer 256 · 5.3 ms · 6 tracks · autosaved 2 min ago")
            .foregroundStyle(.palette.foregroundTertiary)
    }
}
