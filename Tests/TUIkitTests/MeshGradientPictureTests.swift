//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGradientPictureTests.swift
//
//  A mesh gradient as a picture, where the terminal draws them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("Mesh gradients drawn as pictures")
struct MeshGradientPictureTests {
    private let cell = TerminalCellPixels(width: 16, height: 34)

    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    private func rendered<V: View>(_ view: V, width: Int = 20, height: Int = 3) -> (FrameBuffer, TerminalImageStore) {
        let tui = Self.snapshotContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = cell
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return (renderToBuffer(view, context: context), tui.terminalImageStore)
    }

    private func placeholders(_ buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { $0 + $1.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count }
    }

    private static let corners: [SIMD2<Float>] = [[0, 0], [1, 0], [0, 1], [1, 1]]

    /// Red to blue across, black to white down at the left — a pixel's
    /// colour says where it is.
    private static let mesh = MeshGradient(
        width: 2, height: 2, points: corners,
        colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)], smoothsColors: false)

    @Test("A mesh used as a view is a picture where the terminal draws them, and cells elsewhere")
    func meshViewIsAPicture() {
        let (cells, cellStore) = rendered(Self.mesh)
        #expect(placeholders(cells) == 0)
        #expect(cellStore.imageCount == 0)
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(Self.mesh) }
        #expect(placeholders(buffer) == 20 * 3, "every cell of the box")
        #expect(store.imageCount == 1)
    }

    /// Each pixel of the picture is the mesh at that pixel's centre — the same
    /// raster the cells take, at a pixel's scale. A 10 × 2 box of 16 × 34
    /// cells reduces by 2 to 80 × 34 pixels.
    @Test("The picture's pixels are the mesh at each pixel's centre")
    func picturePixelsFollowTheMesh() throws {
        guard case .mesh(let paint) = Self.mesh.paint(in: EnvironmentValues()) else {
            Issue.record("not a mesh")
            return
        }
        let picture = try #require(
            GradientRaster.picture(
                paint: .mesh(paint), frame: GradientFrame(width: 10, height: 2), columns: 10, rows: 2,
                cellPixels: cell))
        #expect(picture.width == 80 && picture.height == 34)
        for x in [0, 13, 40, 79] {
            let blue = Int(((Double(x) + 0.5) / 80 * 255).rounded())
            let offset = (17 * picture.width + x) * 3
            let pixel = Array(picture.bytes[offset..<(offset + 3)])
            #expect(abs(Int(pixel[2]) - blue) <= 1 && abs(Int(pixel[0]) - (255 - blue)) <= 1, "x \(x): \(pixel)")
        }
    }

    /// A box that is a window into a larger extent — a list row under one
    /// `.gradientExtent(.subtree)` mesh — shows its own slice of the mesh.
    @Test("A box inside a larger extent pictures its own slice")
    func windowIntoTheExtent() throws {
        guard case .mesh(let paint) = Self.mesh.paint(in: EnvironmentValues()) else {
            Issue.record("not a mesh")
            return
        }
        let picture = try #require(
            GradientRaster.picture(
                paint: .mesh(paint), frame: GradientFrame(originX: 10, originY: 0, width: 20, height: 2), columns: 10,
                rows: 2, cellPixels: cell))
        // The right half of the mesh: its first pixel is just past the middle.
        let first = Array(picture.bytes[0..<3])
        #expect(abs(Int(first[2]) - 129) <= 1, "\(first)")
    }

    @Test("A translucent mesh, or one whose background shows through clear, stays cells")
    func translucentMeshIsCells() {
        let inset = MeshGradient(
            width: 2, height: 2, points: [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]],
            colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)])
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(inset) }
        #expect(placeholders(buffer) == 0, "a clear background has no pixel to hold it")
        #expect(store.imageCount == 0)
        let backed = MeshGradient(
            width: 2, height: 2, points: [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]],
            colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)], background: .rgb(0, 0, 0))
        let (opaque, _) = KittyGraphics.withSupport(true) { rendered(backed) }
        #expect(placeholders(opaque) == 20 * 3, "an opaque background is a picture")
    }

    @Test("A mesh behind text stays cells")
    func meshBehindTextIsCells() {
        let (buffer, store) = KittyGraphics.withSupport(true) {
            rendered(Text("hello").background(Self.mesh), height: 1)
        }
        #expect(placeholders(buffer) == 0)
        #expect(store.imageCount == 0)
    }
}
