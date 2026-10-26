//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRStyleSequenceTests.swift
//
//  `ANSIRenderer.styleSequence(for:)` writes its parameters into one string
//  instead of building the codes array, growing it by the colours' own arrays,
//  joining and interpolating. These pin the written spelling to the joined one,
//  and a few introducers to their literal bytes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@Suite("A style's SGR introducer is the attributes and colours, joined")
struct SGRStyleSequenceTests {

    /// The seven attributes in emission order, each as the flag it sets and its code.
    private static let attributes: [(code: String, set: @Sendable (inout TextStyle) -> Void)] = [
        ("1", { $0.isBold = true }), ("2", { $0.isDim = true }), ("3", { $0.isItalic = true }),
        ("4", { $0.isUnderlined = true }), ("5", { $0.isBlink = true }), ("7", { $0.isInverted = true }),
        ("9", { $0.isStrikethrough = true }),
    ]

    /// Every arm a colour's parameters can take: none, a slot, an index, an RGB,
    /// the terminal's default, and the two carried colours (spelled through the
    /// reported RGB in the other slot).
    private static let colours: [Color?] = [
        nil, .ansi(.red), .ansi(.brightCyan), .palette256(200), .rgb(1, 2, 3), .rgb(255, 128, 0),
        .default, .terminalForeground, .terminalBackground,
    ]

    private static let depths: [ColorDepth] = [.truecolor, .palette256, .basic16, .noColor]

    /// What `styleSequence` built before: the codes as an array — the attributes
    /// `mask` sets, in order, then each colour's — joined.
    private static func joined(mask: Int, _ style: TextStyle, depth: ColorDepth) -> String? {
        var codes = attributes.indices.filter { mask & (1 << $0) != 0 }.map { attributes[$0].code }
        if let foreground = style.foregroundColor { codes += foreground.foregroundCodes(depth: depth) }
        if let background = style.backgroundColor { codes += background.backgroundCodes(depth: depth) }
        return codes.isEmpty ? nil : "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    @Test("The written introducer is the joined codes, over every attribute set, colour arm and depth")
    func writtenEqualsJoined() {
        let reported = TerminalColors(
            foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
            background: TerminalColors.RGB(red: 40, green: 44, blue: 52))
        // Every attribute set × foreground × background, built once.
        var styles: [(mask: Int, style: TextStyle)] = []
        for mask in 0..<(1 << Self.attributes.count) {
            for foreground in Self.colours {
                for background in Self.colours {
                    var style = TextStyle()
                    for (index, attribute) in Self.attributes.enumerated() where mask & (1 << index) != 0 {
                        attribute.set(&style)
                    }
                    style.foregroundColor = foreground
                    style.backgroundColor = background
                    styles.append((mask, style))
                }
            }
        }
        for terminal in [TerminalColors.unknown, reported] {
            for depth in Self.depths {
                let mismatches = TerminalColors.withCurrent(terminal) {
                    ColorDepth.withCurrent(depth) {
                        styles.filter {
                            ANSIRenderer.styleSequence(for: $0.style) != Self.joined(mask: $0.mask, $0.style, depth: depth)
                        }
                    }
                }
                #expect(mismatches.isEmpty, "\(mismatches.count) styles differ @\(depth), first: \(String(describing: mismatches.first))")
            }
        }
    }

    @Test("A few introducers, byte for byte")
    func literalIntroducers() {
        ColorDepth.withCurrent(.truecolor) {
            var style = TextStyle()
            #expect(ANSIRenderer.styleSequence(for: style) == nil)
            style.isBold = true
            #expect(ANSIRenderer.styleSequence(for: style) == "\u{1B}[1m")
            style.foregroundColor = .rgb(1, 2, 3)
            #expect(ANSIRenderer.styleSequence(for: style) == "\u{1B}[1;38;2;1;2;3m")
            style.backgroundColor = .palette256(17)
            #expect(ANSIRenderer.styleSequence(for: style) == "\u{1B}[1;38;2;1;2;3;48;5;17m")
            style.isBold = false
            style.isInverted = true
            style.foregroundColor = .ansi(.red)
            style.backgroundColor = .default
            #expect(ANSIRenderer.styleSequence(for: style) == "\u{1B}[7;31;49m")
        }
        ColorDepth.withCurrent(.noColor) {
            var style = TextStyle()
            style.foregroundColor = .rgb(1, 2, 3)
            #expect(ANSIRenderer.styleSequence(for: style) == nil)
            style.isUnderlined = true
            #expect(ANSIRenderer.styleSequence(for: style) == "\u{1B}[4m")
        }
    }

    @Test("A translucent colour reaching the emitter is reported, and spelled at full strength")
    func translucentColourReport() {
        // A release build has no assertion, so this report is all an app
        // developer sees of an unmigrated path. A debug build would stop at it,
        // so the reports go to a log of the test's own, through the seam, and
        // the emitter carries on as a release build does.
        let reports = TranslucentReports()
        let opaque = Color.rgb(255, 0, 0)
        let translucent = opaque.opacity(0.5)
        func styles(_ colour: Color) -> [TextStyle] {
            var foreground = TextStyle()
            foreground.foregroundColor = colour
            var background = TextStyle()
            background.backgroundColor = colour
            return [foreground, background]
        }
        ColorDepth.withCurrent(.truecolor) {
            ANSIRenderer.$translucentReporter.withValue(
                { reports.append($0) },
                operation: {
                    for (stated, full) in zip(styles(translucent), styles(opaque)) {
                        #expect(ANSIRenderer.styleSequence(for: stated) == ANSIRenderer.styleSequence(for: full))
                    }
                    #expect(
                        ANSIRenderer.backgroundCode(for: translucent) == ANSIRenderer.backgroundCode(for: opaque))
                })
        }
        // One for each place a colour is spelled: a run's foreground and
        // background, and a line's background. (An underline's colour cannot
        // be translucent: `Text.LineStyle` keeps it without its alpha.)
        #expect(reports.messages.count == 3, "\(reports.messages)")
        #expect(reports.messages.allSatisfy { $0.contains("alpha 128") }, "\(reports.messages)")
        #expect(reports.messages.allSatisfy { $0.contains("Opacity as composition.md") })
        var line = TextStyle()
        line.underline = .some(Text.LineStyle(pattern: .dash, color: translucent))
        #expect(line.lineColour?.isOpaque == true)
    }
}

/// What the emitter reported through ``ANSIRenderer/translucentReporter``.
///
/// `@unchecked Sendable` because the reporter must be `@Sendable`, but only
/// the test that binds it, on its own thread, ever touches it.
private final class TranslucentReports: @unchecked Sendable {
    private(set) var messages: [String] = []

    func append(_ message: String) { messages.append(message) }
}
