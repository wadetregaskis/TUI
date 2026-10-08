//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRasterTests.swift
//
//  An `Image`'s picture behind the raster seam (`_ImageRaster`): the identity
//  it keeps its state at, and what its equality leaves out.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitImage

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("An image's picture behind the raster seam")
struct ImageRasterTests {

    /// A fine black-and-white checkerboard, so a drawn picture and a
    /// placeholder are told apart by every cell.
    private static let pixels = RGBAImage(
        width: 32, height: 32,
        pixels: (0..<(32 * 32)).map { index in
            (index % 32 + index / 32).isMultiple(of: 2) ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0)
        })

    nonisolated private static let source = ImageSource.url("tuikit-test://checkerboard")

    /// Effects off, as a snapshot runs: nothing loads, so a picture draws only
    /// where its loaded phase is already in the state its identity keys.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// One render pass of `image` at the root, through `tui`'s state.
    private func frame(_ image: Image, in tui: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        let context = RenderContext(
            availableWidth: 16, availableHeight: 8, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return renderToBuffer(image, context: context).lines
    }

    /// The source's picture, which first seats the state a finished load
    /// leaves — the phase holding the pixels — wherever it is asked to draw:
    /// the identity the image's host gives its picture. From then on the
    /// source's own picture, the one `Image(_:)` makes, finds it there or
    /// does not.
    private struct LoadedOnce: _ImageRaster {
        let inner = _SourcedImageRaster(source: ImageRasterTests.source, decoded: nil)

        // Drawn once, in a frame no memo serves: nothing compares it.
        func isEqual(to other: any _ImageRaster) -> Bool { false }

        @MainActor
        func sizeThatFits(proposal: ProposedSize, options: _ImageRasterOptions, context: RenderContext) -> ViewSize {
            inner.sizeThatFits(proposal: proposal, options: options, context: context)
        }

        @MainActor
        func renderToBuffer(options: _ImageRasterOptions, context: RenderContext) -> FrameBuffer {
            // Slot 0 is `_ImageCore`'s `StateIndex.phase`.
            let phase: StateBox<ImageLoadingPhase> = context.stateStorage!.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0), default: .loading)
            phase.value = .success(ImageRasterTests.pixels)
            return inner.renderToBuffer(options: options, context: context)
        }
    }

    @Test("A picture keeps its loaded pixels while the image's own sampling comes and goes")
    func samplingTogglesKeepTheLoadedPicture() {
        // What each frame should draw — the picture, already decoded — and
        // what it draws if its state is lost: the placeholder of a load that
        // starts over.
        func drawn(_ modify: (Image) -> Image) -> [String] {
            frame(modify(Image(Self.source, decoded: _DecodedImage(Self.pixels))), in: Self.snapshotContext())
        }
        let placeholder = frame(Image(Self.source), in: Self.snapshotContext())

        // Loaded under the image's own `.interpolation(.none)`, then drawn
        // without it, with `.antialiased(false)`, and at `.high`. Each change
        // is a different sampling factor, or none: if any of them moved the
        // picture to another identity, its phase there would be a fresh
        // `.loading`, and that frame would draw the placeholder.
        let tui = Self.snapshotContext()
        let loaded = frame(Image(raster: LoadedOnce()).interpolation(.none), in: tui)
        #expect(loaded == drawn { $0.interpolation(.none) })
        #expect(loaded != placeholder, "the seated phase drew nothing different, so the case is vacuous")

        let steps: [(String, (Image) -> Image)] = [
            ("no sampling of its own", { $0 }),
            ("antialiased(false)", { $0.antialiased(false) }),
            ("interpolation(.high)", { $0.interpolation(.high) }),
            ("no sampling of its own again", { $0 }),
        ]
        for (label, modify) in steps {
            let lines = frame(modify(Image(Self.source)), in: tui)
            #expect(lines == drawn(modify), "\(label): the picture lost its loaded pixels")
            #expect(lines != placeholder, "\(label): the picture drew its placeholder")
        }
    }

    @Test("Images of one source are equal whatever pixels they carry, decoded or not")
    func equalityLeavesOutDecodedPixels() {
        // The pixels are what the source decodes to, so an image compares
        // equal to itself before and after they arrive. And they come as a
        // fresh `_DecodedImage` each time an image is made again: a body's
        // `Image(_:scale:orientation:label:)` of a `CGImage` every render, an
        // `AsyncImage` whose scale changed since its load
        // (`_DecodedImage.scaled`). An equality that compared them — by
        // object or by pixels — would make every memo above such an image
        // miss, for the same picture.
        let white = _DecodedImage(
            RGBAImage(width: 2, height: 2, pixels: Array(repeating: RGBA(r: 255, g: 255, b: 255), count: 4)))
        let black = _DecodedImage(
            RGBAImage(width: 4, height: 4, pixels: Array(repeating: RGBA(r: 0, g: 0, b: 0), count: 16)))
        #expect(Image(Self.source, decoded: white) == Image(Self.source, decoded: black))
        #expect(Image(Self.source) == Image(Self.source, decoded: white))
        #expect(Image(Self.source, decoded: white) == Image(Self.source, decoded: _DecodedImage(white.pixels)))

        // And still a different source is a different image, pixels or not.
        let other = ImageSource.url("tuikit-test://other")
        #expect(Image(Self.source, decoded: white) != Image(other, decoded: white))
        #expect(Image(Self.source) != Image(other))
    }
}
