//  🖥️ TUI — A Terminal UI framework for Swift
//  MixerClip+Parts.swift
//
//  The mixing desk's sound and the pictures drawn from it: the session's
//  channels, what each plays at any instant of the loop, the levels its fader,
//  pan, mute and solo let through, and the hand-drawn parts — the arrangement's
//  lanes, the spectrum and the main out's LED ladders — built as attributed text.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// One channel of the session.
struct MixChannel {
    let name: String
    /// What is on its inserts, as the strip lists them.
    let inserts: String
    let colour: Color
    /// The colour of its clips in the arrangement: the channel's, darkened.
    let clipColour: Color
    let fader: Double
    let pan: Double
}

/// The session: eight bars of the song in view, the first six of them looped
/// at 160 BPM — nine seconds, so the loop is the clip.
enum Session {
    static let loopSeconds = 9.0
    /// Beats a second: 160 BPM.
    static let beatsPerSecond = 8.0 / 3
    static let bars = 8
    static let loopBars = 6
    static let cellsPerBar = 8
    static var cells: Int { bars * cellsPerBar }
    static var loopCells: Int { loopBars * cellsPerBar }
    /// The bar the loop starts at, as the ruler numbers it: mid-song.
    static let firstBar = 17

    static let channels: [MixChannel] = [
        MixChannel(name: "Kick", inserts: "Gate · EQ", colour: .rgb(255, 104, 84), clipColour: .rgb(110, 34, 28),
                   fader: 0.69, pan: 0),
        MixChannel(name: "Snare", inserts: "Comp · Verb", colour: .rgb(255, 176, 64), clipColour: .rgb(104, 64, 18),
                   fader: 0.62, pan: 0.25),
        MixChannel(name: "Hats", inserts: "EQ · Delay", colour: .rgb(236, 222, 92), clipColour: .rgb(84, 78, 22),
                   fader: 0.54, pan: -0.5),
        MixChannel(name: "Bass", inserts: "Drive · Comp", colour: .rgb(176, 120, 255), clipColour: .rgb(60, 36, 104),
                   fader: 0.62, pan: 0),
        MixChannel(name: "Keys", inserts: "Chorus · EQ", colour: .rgb(64, 212, 196), clipColour: .rgb(18, 84, 78),
                   fader: 0.62, pan: 0),
        MixChannel(name: "Vox", inserts: "Tune · Verb", colour: .rgb(255, 116, 186), clipColour: .rgb(104, 30, 70),
                   fader: 0.69, pan: 0),
    ]

    /// A meter's scale: green, amber from −6 dB or so, red at the top.
    static let meterStops = [
        Gradient.Stop(color: .rgb(40, 210, 110), location: 0),
        Gradient.Stop(color: .rgb(120, 230, 80), location: 0.55),
        Gradient.Stop(color: .rgb(250, 200, 40), location: 0.78),
        Gradient.Stop(color: .rgb(255, 60, 50), location: 1),
    ]
    /// The same scale, unlit: the LEDs a meter has not reached.
    static let unlitStops = [
        Gradient.Stop(color: .rgb(22, 52, 34), location: 0),
        Gradient.Stop(color: .rgb(36, 58, 26), location: 0.55),
        Gradient.Stop(color: .rgb(62, 52, 18), location: 0.78),
        Gradient.Stop(color: .rgb(70, 24, 22), location: 1),
    ]

    /// The scale's colour at `fraction` of the way up.
    static func meterColour(_ fraction: Double, lit: Bool = true) -> Color {
        let stops = lit ? meterStops : unlitStops
        let value = min(1, max(0, fraction))
        for index in 1..<stops.count where value <= stops[index].location {
            let (low, high) = (stops[index - 1], stops[index])
            let phase = (value - low.location) / (high.location - low.location)
            return Color.lerp(low.color, high.color, phase: phase)
        }
        return stops[stops.count - 1].color
    }
}

/// What the desk's controls are set to.
struct MixState: Equatable {
    var faders = Session.channels.map(\.fader)
    var pans = Session.channels.map(\.pan)
    var muted: Set<Int> = []
    var soloed: Set<Int> = []
    var output = 0.75

    static let start = Self()

    func audible(_ channel: Int) -> Bool {
        !muted.contains(channel) && (soloed.isEmpty || soloed.contains(channel))
    }

    /// A fader's gain: unity at three quarters of the way up, +6 dB or so at the top.
    static func gain(_ fader: Double) -> Double { pow(fader / 0.75, 2.4) }

    static func decibels(_ fader: Double) -> String {
        guard fader > 0.01 else { return "  −∞ dB" }
        let value = 20 * log10(gain(fader))
        return String(format: "%+5.1f dB", value).replacingOccurrences(of: "-", with: "−")
    }

    static func panText(_ pan: Double) -> String {
        let amount = Int((abs(pan) * 100).rounded())
        return amount == 0 ? "C" : pan < 0 ? "L\(amount)" : "R\(amount)"
    }

    /// A channel's level, left and right, after its fader and pan, at `time`.
    func level(_ channel: Int, at time: Double) -> (left: Double, right: Double) {
        guard audible(channel) else { return (0, 0) }
        let signal = Signal.source(channel, at: time) * Self.gain(faders[channel])
        let pan = pans[channel]
        let left = signal * min(1, 1 - pan) * (1 + 0.05 * Signal.osc(41 + channel * 5, time))
        let right = signal * min(1, 1 + pan) * (1 + 0.05 * Signal.osc(37 + channel * 3, time, 0.5))
        return (left, right)
    }

    /// The main bus, left and right: the channels summed, through its fader —
    /// scaled so the mix as it stands peaks a little short of full
    /// scale, and the bass pushed to the top tips it over.
    func mainBus(at time: Double) -> (left: Double, right: Double) {
        var (left, right) = (0.0, 0.0)
        for channel in Session.channels.indices {
            let level = level(channel, at: time)
            left += level.left
            right += level.right
        }
        let gain = Self.gain(output) * 0.364
        return (left * gain, right * gain)
    }

    /// The highest a level reached over the last `seconds`, sampled a frame at a time.
    static func held(seconds: Double = 1.2, at time: Double, _ level: (Double) -> Double) -> Double {
        let samples = Int(seconds * 30)
        return (0..<samples).reduce(0) { highest, step in max(highest, level(time - Double(step) / 30)) }
    }

    /// A level as a meter shows it: up at once, down at `release` of the scale
    /// a second, as a desk's meters fall — so a kick's thump rises in a frame
    /// and drains away rather than dropping out.
    static func ballistic(release: Double = 1.8, at time: Double, _ level: (Double) -> Double) -> Double {
        let samples = Int((30 / release).rounded(.up))
        return (0..<samples).reduce(0) { shown, step in
            max(shown, level(time - Double(step) / 30) - release * Double(step) / 30)
        }
    }
}

/// What the session plays: each channel's level as a function of where in the
/// loop the playhead is, so the meters bounce to the beat and a frame of the
/// loop's end is a frame of its start.
enum Signal {
    /// A sine of `cycles` whole turns over the loop: every wobble ends where it began.
    static func osc(_ cycles: Int, _ time: Double, _ phase: Double = 0) -> Double {
        sin(2 * Double.pi * (Double(cycles) * time / Session.loopSeconds + phase))
    }

    static func wrapped(_ time: Double) -> Double {
        let remainder = time.truncatingRemainder(dividingBy: Session.loopSeconds)
        return remainder < 0 ? remainder + Session.loopSeconds : remainder
    }

    /// A channel's source, before its fader: 0…1.
    static func source(_ channel: Int, at time: Double) -> Double {
        let time = wrapped(time)
        let beat = time * Session.beatsPerSecond
        let beatIndex = Int(beat)
        let phase = beat - Double(beatIndex)
        switch channel {
        case 0:
            return 0.06 + 0.84 * exp(-phase * 5)
        case 1:
            let hit = !beatIndex.isMultiple(of: 2) ? 0.8 * exp(-phase * 4) : 0.12 * exp(-phase * 9)
            return 0.05 + hit
        case 2:
            let eighth = beat * 2 - Double(Int(beat * 2))
            let accent = !Int(beat * 2).isMultiple(of: 2) ? 0.55 : 0.34
            return 0.08 + accent * exp(-eighth * 7)
        case 3:
            let pump = 1 - 0.45 * exp(-phase * 4)
            return (0.66 + 0.1 * osc(16, time)) * pump
        case 4:
            return 0.44 + 0.14 * osc(4, time) + 0.05 * osc(48, time, 0.3)
        default:
            guard Arrangement.voxSings(beat: beatIndex) else { return 0.03 }
            return 0.48 + 0.2 * abs(osc(56, time)) + 0.12 * osc(23, time, 0.2)
        }
    }
}

/// A run of cells drawn alike, for building a line of attributed text.
private struct Cell: Equatable {
    var glyph: Character
    var foreground: Color
    var background: Color?
}

/// Cells to one attributed string, neighbours drawn alike in one run.
private func attributed(_ cells: [Cell]) -> AttributedString {
    var result = AttributedString()
    var start = 0
    while start < cells.count {
        var end = start + 1
        while end < cells.count, cells[end].foreground == cells[start].foreground,
              cells[end].background == cells[start].background { end += 1 }
        var run = AttributedString(String(cells[start..<end].map(\.glyph)))
        run.foregroundColor = cells[start].foreground
        if let background = cells[start].background { run.backgroundColor = background }
        result += run
        start = end
    }
    return result
}

/// The arrangement: each channel's lane of clips over the loop's eight bars,
/// and the playhead crossing them.
enum Arrangement {
    /// A clip: its first cell, its length in cells, its name.
    struct Region {
        let start: Int
        let length: Int
        let name: String
    }

    /// The vocal sings right through the loop — so a solo, wherever the
    /// playhead is, has a voice to show — but for a breath at the end of each
    /// two-bar line.
    static func voxSings(beat: Int) -> Bool { beat % 8 != 7 }

    static let regions: [[Region]] = [
        [Region(start: 0, length: 64, name: "Kick 4/4")],
        [Region(start: 0, length: 32, name: "Snare A"), Region(start: 32, length: 32, name: "Snare B")],
        [Region(start: 0, length: 64, name: "Hats 8ths")],
        [Region(start: 0, length: 32, name: "Bass riff"), Region(start: 32, length: 32, name: "Bass riff")],
        [Region(start: 0, length: 64, name: "Pad · Am9")],
        [Region(start: 0, length: 24, name: "Verse"), Region(start: 24, length: 24, name: "Hook"),
         Region(start: 48, length: 16, name: "Ad-lib")],
    ]

    /// What a lane draws in a clip's cell, after its name: the hits, the
    /// notes or the waveform of the part.
    static func glyph(_ channel: Int, cell: Int) -> Character {
        let waves: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]
        switch channel {
        case 0: return cell.isMultiple(of: 2) ? "▌" : " "
        case 1: return cell % 4 == 2 ? "▌" : cell % 8 == 7 ? "╷" : " "
        case 2: return !cell.isMultiple(of: 2) ? "╻" : "╷"
        case 3:
            let height = 3 + 2 * sin(Double(cell) * 1.3) + sin(Double(cell) * 0.4)
            return waves[min(6, max(0, Int(height)))]
        case 4: return cell % 8 == 7 ? " " : cell % 8 < 4 ? "▬" : "━"
        default:
            let height = 3.2 + 2.2 * sin(Double(cell) * 0.9) * cos(Double(cell) * 0.37)
            return waves[min(6, max(0, Int(height)))]
        }
    }

    /// The ruler: bar numbers, the loop brace's tint, and the playhead's ▼.
    static func ruler(playhead: Int) -> AttributedString {
        // The loop's bars on a tint of their own, the rest of the song plain.
        func ground(_ cell: Int) -> Color { cell < Session.loopCells ? .rgb(20, 56, 66) : .rgb(26, 30, 36) }
        var cells = (0..<Session.cells).map { cell in
            Cell(glyph: "·", foreground: .rgb(90, 104, 120), background: ground(cell))
        }
        for bar in 0..<Session.bars {
            let label = Array(String(Session.firstBar + bar))
            for (offset, glyph) in label.enumerated() {
                let cell = bar * Session.cellsPerBar + offset
                cells[cell] = Cell(glyph: glyph, foreground: .rgb(170, 200, 210), background: ground(cell))
            }
            cells[bar * Session.cellsPerBar + 4].glyph = "╵"
        }
        cells[playhead] = Cell(glyph: "▼", foreground: .rgb(255, 255, 255), background: ground(playhead))
        return attributed(cells)
    }

    /// A channel's lane: its clips, named and drawn, greyed when it cannot be heard.
    static func lane(_ channel: Int, playhead: Int, audible: Bool) -> AttributedString {
        let info = Session.channels[channel]
        var cells = (0..<Session.cells).map { cell in
            Cell(glyph: cell.isMultiple(of: Session.cellsPerBar) ? "┊" : " ", foreground: .rgb(44, 50, 58), background: nil)
        }
        for region in regions[channel] {
            let name = Array(" " + region.name + " ")
            for offset in 0..<region.length {
                let cell = region.start + offset
                let glyph = offset < name.count ? name[offset] : glyph(channel, cell: cell)
                let foreground = audible ? (offset < name.count ? Color.rgb(250, 250, 250) : info.colour) : .rgb(110, 110, 116)
                let background = audible ? info.clipColour : Color.rgb(40, 40, 44)
                cells[cell] = Cell(glyph: glyph, foreground: foreground, background: background)
            }
        }
        cells[playhead].glyph = "│"
        cells[playhead].foreground = .rgb(255, 255, 255)
        return attributed(cells)
    }
}

/// The spectrum analyser: a bar per band, coloured up its height, each with a
/// cap that holds its peak a moment before it falls.
enum Spectrum {
    static let bands = 15
    static let rows = 7

    /// Where in the bands each channel sits, and how wide it spreads.
    private static let placement: [(centre: Double, spread: Double)] = [
        (0.6, 1.4), (6, 4), (12.6, 2.6), (2.4, 1.8), (7, 2.8), (8.6, 2.1),
    ]

    static func bandLevels(_ state: MixState, at time: Double) -> [Double] {
        let levels = Session.channels.indices.map { channel in
            MixState.ballistic(at: time) { moment in
                let level = state.level(channel, at: moment)
                return max(level.left, level.right)
            }
        }
        return (0..<bands).map { band in
            var sum = 0.0
            for (channel, place) in placement.enumerated() {
                let distance = (Double(band) - place.centre) / place.spread
                let weight = exp(-distance * distance)
                sum += pow(levels[channel] * weight, 2)
            }
            let shimmer = 0.93 + 0.07 * Signal.osc(29 + band * 13, time)
            return min(1.05, sum.squareRoot() * shimmer * 1.3 * (1.02 - Double(band) * 0.022))
        }
    }

    /// The analyser's rows, top first.
    static func lines(_ state: MixState, at time: Double) -> [AttributedString] {
        let now = bandLevels(state, at: time)
        // The peaks: the highest each band reached over the last 0.8 s.
        var peaks = now
        for step in 1..<16 {
            for (band, level) in bandLevels(state, at: time - Double(step) / 20).enumerated() {
                peaks[band] = max(peaks[band], level - Double(step) * 0.012)
            }
        }
        let eighths: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        return (0..<rows).map { rowFromTop in
            let row = rows - 1 - rowFromTop
            let colour = Session.meterColour((Double(row) + 0.5) / Double(rows))
            var cells: [Cell] = []
            for band in 0..<bands {
                let height = min(1, now[band]) * Double(rows)
                let fill = max(0, min(8, Int(((height - Double(row)) * 8).rounded())))
                let peakRow = min(rows - 1, Int(min(0.999, peaks[band]) * Double(rows)))
                if fill == 0 && peakRow == row && peaks[band] > 0.05 {
                    cells.append(Cell(glyph: "▔", foreground: .rgb(235, 240, 245), background: nil))
                } else {
                    cells.append(Cell(glyph: eighths[fill], foreground: colour, background: nil))
                }
                if band < bands - 1 { cells.append(Cell(glyph: " ", foreground: colour, background: nil)) }
            }
            return attributed(cells)
        }
    }
}

/// The main out's LED ladders: two columns, left and right, lit up from the
/// bottom with a held peak above, beside their scale.
enum MainLadder {
    static let rows = 12
    /// The ladder's rows, top first, in dBFS: each lit once the level reaches it.
    private static let marks = [0, -3, -6, -9, -12, -15, -18, -24, -30, -36, -48, -60]

    static func lines(level: (left: Double, right: Double), peak: (left: Double, right: Double)) -> [AttributedString] {
        (0..<rows).map { rowFromTop in
            let row = rows - 1 - rowFromTop
            let fraction = (Double(row) + 0.5) / Double(rows)
            let mark = Double(marks[rowFromTop])
            /// The top row the level reaches, counted from the bottom (−1 for none).
            func reach(_ value: Double) -> Int {
                let decibels = value > 0.000_001 ? 20 * log10(value) : -120
                return Array(marks.reversed()).lastIndex { decibels >= Double($0) } ?? -1
            }
            func led(_ value: Double, _ held: Double) -> Cell {
                let lit = 20 * log10(max(value, 0.000_001)) >= mark
                let isPeak = reach(held) == row && held > 0.01
                return Cell(glyph: "▆", foreground: Session.meterColour(fraction, lit: lit || isPeak), background: nil)
            }
            let left = led(level.left, peak.left)
            let right = led(level.right, peak.right)
            let label = Array(String(format: "%3d ", marks[rowFromTop]).replacingOccurrences(of: "-", with: "−")).map {
                Cell(glyph: $0, foreground: .rgb(120, 130, 140), background: nil)
            }
            var cells = label
            cells += [left, left, left, Cell(glyph: " ", foreground: .rgb(0, 0, 0), background: nil), right, right, right]
            return attributed(cells)
        }
    }
}
