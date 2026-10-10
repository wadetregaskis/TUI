//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageNaturalSizeTests.swift
//
//  An image that is not resizable takes its natural size, as SwiftUI's does —
//  its size in points over the terminal cell's — where the cell's size in
//  points is known, and fits what it is offered where it is not. And how the
//  render loop knows a cell's size in points, host by host.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIkitBitmaps
import TUIkitImage

#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit
#endif

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Images at their natural size")
struct ImageNaturalSizeTests {

    private static let red = RGBA(r: 255, g: 0, b: 0)

    /// A seven-point cell, twice as tall as it is wide: Apple Terminal's.
    private static let cell = TerminalCellPoints(width: 7, height: 14)

    /// A solid `width` × `height`-pixel picture, already decoded, at `scale`.
    private func picture(_ width: Int, _ height: Int, scale: Double = 1) -> Image {
        Image(
            .url("tuikit-test://natural-\(width)x\(height)@\(scale)"),
            decoded: _DecodedImage(
                RGBAImage(width: width, height: height, pixels: Array(repeating: Self.red, count: width * height)),
                scale: scale))
    }

    /// The box `view` draws in — or with `measuring`, the size it says it
    /// takes — offered `width` × `height` cells, with the cell's size in
    /// points `points`.
    private func box(
        _ view: some View, width: Int = 80, height: Int = 24, points: TerminalCellPoints? = cell,
        measuring: Bool = false
    ) -> (width: Int, height: Int) {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2
        environment.imageCellPoints = points
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        if measuring {
            let size = measureChild(view, proposal: ProposedSize(width: width, height: height), context: context)
            return (size.width, size.height)
        }
        let buffer = renderToBuffer(view, context: context)
        return (buffer.width, buffer.height)
    }

    @Test("An image that is not resizable takes its size in points, in cells, whatever it is offered")
    func naturalSize() {
        // 140 × 70 pixels at a pixel a point, in 7 × 14-point cells.
        #expect(box(picture(140, 70)) == (20, 5))
        #expect(box(picture(140, 70), width: 8, height: 2, measuring: true) == (20, 5), "larger than it is offered")
        #expect(box(picture(140, 70), width: 8, height: 2) == (8, 2), "and drawn cut to the space it was given")
        #expect(box(HStack(spacing: 0) { picture(140, 70); Text("|") }) == (21, 5), "the stack lays it out at 20")
    }

    @Test("Cut to its space, it shows its top-leading part")
    func cutFromTheTopLeading() {
        let pixels = (0..<(140 * 70)).map { index in index % 140 < 70 ? Self.red : RGBA(r: 0, g: 0, b: 255) }
        let image = Image(
            .url("tuikit-test://halves"), decoded: _DecodedImage(RGBAImage(width: 140, height: 70, pixels: pixels)))
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPoints = Self.cell
        let context = RenderContext(availableWidth: 8, availableHeight: 2, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let drawn = renderToBuffer(image.imageColorMode(.trueColor), context: context).lines.joined()
        #expect(drawn.contains("255;0;0") && !drawn.contains("0;0;255"), "only the red left half shows")
    }

    @Test("Its pixels over its scale are its size in points")
    func scaleHalvesIt() {
        #expect(box(picture(140, 70, scale: 2)) == (10, 3))
        // Rounded to whole cells, and never less than one.
        #expect(box(picture(2, 2, scale: 2)) == (1, 1))
    }

    @Test("Where the cell's size in points is unknown, it fits what it is offered, as it always did")
    func unknownCellFits() {
        #expect(box(picture(140, 70), width: 20, height: 24, points: nil) == (20, 5))
        #expect(box(picture(140, 70), width: 10, height: 24, points: nil) == (10, 3))
    }

    @Test("A resizable image fills its frame, and a fit target other than the natural size fits it")
    func resizableAndFitTargetsFit() {
        #expect(box(picture(140, 70).resizable(), width: 30, height: 4) == (30, 4))
        #expect(box(picture(140, 70).resizable().scaledToFit(), width: 10, height: 24) == (10, 3))
        #expect(box(picture(140, 70).imageFitTarget(.proposedSize), width: 10, height: 24) == (10, 3))
    }

    @Test("Zoom scales the natural size")
    func zoomScalesIt() {
        #expect(box(picture(140, 70).imageZoom(2)) == (40, 10))
    }

    @Test("A picture too large to count is held to the most cells an image takes")
    func hugePicturesAreBounded() {
        let size = box(picture(140, 70), points: TerminalCellPoints(width: 0.01, height: 0.01), measuring: true)
        #expect(size.width == _ImageCore.maximumNaturalCells && size.height == _ImageCore.maximumNaturalCells)
    }

    #if canImport(AppKit)
        /// A `width` × `height` CGImage of one colour.
        private func solid(width: Int, height: Int) -> CGImage {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            let context = CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }

        @Test("A CGImage is its pixels over its scale; an NSImage, its size")
        func appKitImages() {
            let cgImage = solid(width: 140, height: 70)
            #expect(box(Image(decorative: cgImage, scale: 1)) == (20, 5))
            #expect(box(Image(cgImage, scale: 2, label: Text("half"))) == (10, 3))
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 280, height: 140))
            #expect(box(Image(nsImage: nsImage)) == (40, 10), "the NSImage's size, not its pixels")
        }

        /// The size is read when the `Image` is made, so a memo that compares
        /// images by their names must see a resized `NSImage` as another image,
        /// or it keeps drawing the old size.
        @Test("An NSImage given a new size is another image, at its new size")
        func resizedNSImageIsAnotherImage() {
            let nsImage = NSImage(cgImage: solid(width: 140, height: 70), size: NSSize(width: 140, height: 70))
            let before = Image(nsImage: nsImage)
            #expect(Image(nsImage: nsImage) == before, "the same NSImage at the same size is the same image")
            nsImage.size = NSSize(width: 280, height: 140)
            let after = Image(nsImage: nsImage)
            #expect(after != before)
            #expect(box(after) == (40, 10))
        }
    #endif

    // MARK: - A cell's size in points, host by host

    @Test("The loop publishes the cell's size in points where the host's pixels are calibrated, and not elsewhere")
    func loopPublishesPoints() {
        func published(_ calibration: CellPointsCalibration?) -> TerminalCellPoints? {
            let saved = TerminalClient.cellPointsCalibration
            TerminalClient.cellPointsCalibration = calibration
            defer { TerminalClient.cellPointsCalibration = saved }
            let harness = RenderLoopHarness()
            harness.terminal.reportedCellPixels = TerminalCellPixels(width: 16, height: 34)
            let loop = harness.loop(CellPointsProbeApp())
            loop.render()
            return CellPointsProbe.seen
        }
        let ghostty = CellPointsCalibration(pixelsPerPointWide: 2, pixelsPerPointHigh: 2)
        #expect(published(ghostty) == TerminalCellPoints(width: 8, height: 17))
        #expect(published(nil) == nil)
    }

    private typealias Host = TerminalClient.CellPointsHost

    private func calibration(
        _ host: Host, reported: TerminalCellPixels? = TerminalCellPixels(width: 14, height: 34),
        area: (width: Int, height: Int)? = nil, scale: Double? = nil
    ) -> CellPointsCalibration? {
        TerminalClient.calibration(
            host: host, reportedCell: reported, grid: (80, 25), textArea: { area }, localDisplayScale: { scale })
    }

    @Test("Apple Terminal and Warp report points")
    func pointHosts() {
        #expect(calibration(Host(isAppleTerminal: true)) == .points)
        #expect(calibration(Host(isWarp: true)) == .points)
    }

    @Test("iTerm2's cell is its text area over the grid, in points")
    func iTerm2() throws {
        // Measured: 80 × 25 cells, 1120 × 850 reported pixels, `CSI 14 t` 570 × 458.
        let found = try #require(calibration(Host(isITerm2: true), area: (570, 458)))
        let points = found.points(for: TerminalCellPixels(width: 14, height: 34))
        #expect(abs(points.width - 7.125) < 0.001 && abs(points.height - 18.32) < 0.001)
        #expect(calibration(Host(isITerm2: true), area: nil) == nil, "no answer, no points")
    }

    @Test("Ghostty's pixels are the display's, so it needs the display's scale")
    func ghostty() throws {
        let found = try #require(calibration(Host(isGhostty: true), reported: TerminalCellPixels(width: 16, height: 34), scale: 2))
        #expect(found.points(for: TerminalCellPixels(width: 16, height: 34)) == TerminalCellPoints(width: 8, height: 17))
        #expect(calibration(Host(isGhostty: true), scale: nil) == nil, "away from the terminal's Mac, unknown")
    }

    @Test("tmux and unmeasured hosts have no points")
    func unknownHosts() {
        #expect(calibration(Host(isTmux: true, isAppleTerminal: true)) == nil)
        #expect(calibration(Host()) == nil)
    }

    @Test("A session is local when the terminal named itself and no ssh session is in the way")
    func localSession() {
        #expect(TerminalClient.isLocalSession(["TERM_PROGRAM": "ghostty"]))
        #expect(!TerminalClient.isLocalSession(["TERM_PROGRAM": "ghostty", "SSH_CONNECTION": "a b c d"]))
        #expect(!TerminalClient.isLocalSession(["TERM": "xterm-ghostty"]), "TERM travels over ssh")
    }

    @Test("The text area's reply is read, and nothing else is")
    func textAreaReply() {
        func parse(_ text: String) -> [Int]? {
            TerminalTextAreaQuery.parse(Array(text.utf8)).map { [$0.width, $0.height] }
        }
        #expect(parse("\u{1B}[4;458;570t\u{1B}[1;1R") == [570, 458])
        #expect(parse("x\u{1B}[4;458;570t") == [570, 458])
        #expect(parse("\u{1B}[1;1R") == nil)
        #expect(parse("\u{1B}[4;0;570t") == nil)
        #expect(TerminalTextAreaQuery.isReply(Array("\u{1B}[4;458;570t".utf8)[...]))
    }
}

/// What the last frame's root environment said a cell is in points.
@MainActor
private enum CellPointsProbe {
    static var seen: TerminalCellPoints?
}

/// An app whose one view records the cell's size in points it was drawn with.
private struct CellPointsProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            CellPointsReader()
        }
    }
}

private struct CellPointsReader: View {
    @Environment(\.imageCellPoints) private var points

    var body: some View {
        CellPointsProbe.seen = points
        return Text(verbatim: "probe")
    }
}
