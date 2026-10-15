//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StripeLegibilityTests.swift
//
//  A table stripes every other row by default (decisions A29), so the stripe
//  is drawn on every palette at every depth an app meets — and a stripe the
//  palettes were never tuned for has to be checked on all of them. Measured on
//  the entries the terminal PAINTS, not on the colour asked for: the first
//  sweep found the 256-colour cube drawing five palettes' stripe in a selected
//  row's own entry and two of them as a loud `#005f00` on black, and the
//  sixteen slots drawing Red Sands' rows on red.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitStyling
import TUIkitTables
@testable import TUIkitTestSupport

@MainActor
@Suite("Stripes stay quiet and readable")
struct StripeLegibilityTests {

    /// The palettes that state their own colours, as the contrast audits sweep.
    private static var statedPalettes: [any Palette] {
        PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    }

    /// `colour` as the terminal paints it at `depth`, as 0xRRGGBB: through the
    /// cube at 256 colours, through the slot table (xterm's, until a terminal
    /// reports one) at 16.
    nonisolated private static func painted(_ colour: Color, at depth: ColorDepth) -> Color? {
        switch depth {
        case .palette256:
            return colour.downsampledToPalette256().rgbComponents.map { Color.rgb($0.red, $0.green, $0.blue) }
        case .basic16:
            guard case .ansi(let slot) = colour.downsampledToANSI16().value else { return nil }
            let packed = RowFills.reportedTable()[Int(slot.rawValue)]
            return .rgb(UInt8(packed >> 16 & 0xFF), UInt8(packed >> 8 & 0xFF), UInt8(packed & 0xFF))
        default:
            return colour.rgbComponents.map { Color.rgb($0.red, $0.green, $0.blue) }
        }
    }

    /// One palette's stripe over one ground at one depth, with what it is
    /// measured against, all as painted.
    private struct Measured {
        let stripe: Color
        let ground: Color
        let text: Color
        let fills: [Color]
        let selection: Color?
    }

    nonisolated private static func measure(_ palette: any Palette, over ground: Color, at depth: ColorDepth) -> Measured? {
        withColorDepth(depth) {
            guard let stripe = palette.stripeFill(over: ground, at: depth),
                let shownStripe = painted(stripe, at: depth),
                let shownGround = painted(ground, at: depth),
                let text = painted(palette.foreground, at: depth)
            else { return nil }
            let fills = palette.rowFills(at: depth, over: ground == palette.background ? nil : ground)
            let all = fills.map { [$0.selection, $0.focusDim, $0.focusBright, $0.emphasisDim, $0.emphasisBright] } ?? []
            return Measured(
                stripe: shownStripe, ground: shownGround, text: text,
                fills: all.compactMap { painted($0, at: depth) },
                selection: fills.flatMap { painted($0.selection, at: depth) })
        }
    }

    /// The grounds a stripe is drawn over: the page, and the surface a `TabView`
    /// body or a `.surface` table lifts its rows onto.
    nonisolated private static func grounds(of palette: any Palette, at depth: ColorDepth) -> [(String, Color)] {
        withColorDepth(depth) {
            [("page", palette.background.resolve(with: palette)),
             ("surface", palette.liftedBackground.resolve(with: palette))]
        }
    }

    @Test(
        "A stripe shows, is no highlight, and stays quieter than a selection",
        arguments: [ColorDepth.palette256, .basic16])
    func quietOnCoarseTerminals(depth: ColorDepth) {
        for palette in Self.statedPalettes {
            for (groundName, ground) in Self.grounds(of: palette, at: depth) {
                guard let measured = Self.measure(palette, over: ground, at: depth) else { continue }
                let entry = "\(palette.name) over its \(groundName) at \(depth)"
                #expect(measured.stripe != measured.ground, "\(entry): the stripe is the ground")
                #expect(!measured.fills.contains(measured.stripe), "\(entry): the stripe is a highlight's fill")
                if let selection = measured.selection {
                    #expect(
                        measured.stripe.contrastRatio(against: measured.ground)
                            < selection.contrastRatio(against: measured.ground),
                        "\(entry): the stripe is louder than a selected row")
                }
            }
        }
    }

    @Test("The text stays readable on a stripe", arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func readable(depth: ColorDepth) {
        for palette in Self.statedPalettes {
            for (groundName, ground) in Self.grounds(of: palette, at: depth) {
                guard let measured = Self.measure(palette, over: ground, at: depth) else { continue }
                let onStripe = measured.text.contrastRatio(against: measured.stripe)
                let onGround = measured.text.contrastRatio(against: measured.ground)
                #expect(
                    onStripe >= min(4.5, 0.8 * onGround) - 0.005,
                    "\(palette.name) over its \(groundName) at \(depth): text \(onStripe) on the stripe, \(onGround) off it")
            }
        }
    }

    @Test("A 256-colour terminal still stripes every palette")
    func stripesSurviveTheCube() {
        let unstriped = Self.statedPalettes.filter { palette in
            Self.measure(palette, over: palette.background, at: .palette256) == nil
        }
        #expect(unstriped.isEmpty, "\(unstriped.map(\.name)) draw no stripe at 256 colours")
    }

    @Test("A table draws the stripe the rule chose, on the cube")
    func tableDrawsTheChosenEntry() throws {
        let palette = try #require(Self.statedPalettes.first { $0.name == "Green" })
        let chosen = try #require(palette.stripeFill(over: palette.background, at: .palette256))
        guard case .palette256(let index) = chosen.value else {
            Issue.record("expected a cube entry, got \(chosen)")
            return
        }
        struct Row: Identifiable { let id: Int; let name: String }
        let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }
        let buffer = withColorDepth(.palette256) {
            var context = makeRenderContext(width: 30, height: 10)
            context.environment.palette = palette
            return renderToBuffer(Table(rows) { TableColumn("Name", value: \Row.name) }, context: context)
        }
        let row1 = buffer.lines.first { $0.stripped.contains("row1") } ?? ""
        #expect(row1.contains("48;5;\(index)m") || row1.contains("48;5;\(index);"), "row1 is \(row1.debugDescription)")
    }
}
