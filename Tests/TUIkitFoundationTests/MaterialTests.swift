//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MaterialTests.swift
//
//  Materials as a translucent palette surface (refusal review O5 (b)): the
//  thicknesses' opacities, the bar's surface, and the active appearance.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("Materials")
struct MaterialTests {

    private func environment(appearsActive: Bool = true) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.appearsActive = appearsActive
        return environment
    }

    private func colour(_ style: some ShapeStyle, in environment: EnvironmentValues) -> Color? {
        style.paint(in: environment).solid
    }

    @Test("A thicker material is a more opaque surface, ultra-thin to ultra-thick")
    func thicknessIsOpacity() {
        let materials: [Material] = [.ultraThin, .thin, .regular, .thick, .ultraThick]
        let alphas = materials.compactMap { colour($0, in: environment())?.alpha }
        #expect(alphas.count == 5)
        #expect(alphas == alphas.sorted() && Set(alphas).count == 5, "\(alphas)")
        #expect(alphas.allSatisfy { $0 < 255 }, "every one is translucent while active")
        #expect(colour(Material.regular, in: environment()) == Color.palette.background.opacity(0.65))
    }

    @Test("The bar material is the bars' surface; the rest are the page's")
    func barSurface() {
        #expect(colour(Material.bar, in: environment()) == Color.palette.statusBarBackground.opacity(0.8))
        #expect(colour(Material.thin, in: environment())?.opaqueSpelling == Color.palette.background)
    }

    @Test("The shape-style spellings are the materials")
    func spellings() {
        func material(_ style: Material) -> Material { style }
        #expect(material(.regularMaterial) == .regular)
        #expect(material(.thickMaterial) == .thick)
        #expect(material(.thinMaterial) == .thin)
        #expect(material(.ultraThinMaterial) == .ultraThin)
        #expect(material(.ultraThickMaterial) == .ultraThick)
    }

    @Test("A material that does not appear active is its surface at full strength")
    func inactiveIsOpaque() {
        let inactiveScene = environment(appearsActive: false)
        #expect(colour(Material.thin, in: inactiveScene) == Color.palette.background)
        // Its own appearance wins over the scene's, either way.
        #expect(colour(Material.thin.materialActiveAppearance(.active), in: inactiveScene)?.alpha ?? 255 < 255)
        #expect(colour(Material.thin.materialActiveAppearance(.inactive), in: environment()) == Color.palette.background)
        #expect(colour(Material.thin.materialActiveAppearance(.matchWindow), in: inactiveScene) == Color.palette.background)
    }

    @Test("The environment's appearance reaches a material that asks for none, and a style can set it")
    func environmentAppearance() {
        var forcedInactive = environment()
        forcedInactive.materialActiveAppearance = .inactive
        #expect(colour(Material.thin, in: forcedInactive) == Color.palette.background)
        #expect(colour(Material.thin.materialActiveAppearance(.active), in: forcedInactive)?.alpha ?? 255 < 255)
        let styled = Material.thin.materialActiveAppearance(.inactive) as any ShapeStyle
        #expect(colour(AnyShapeStyleBox(styled), in: environment()) == Color.palette.background)
        let wrapped = ShapeStyleWrapperProbe.inactive(.thinMaterial)
        #expect(colour(wrapped, in: environment()) == Color.palette.background)
    }

    @Test("Behind a view, a material lets what is under it show through, tinted")
    func compositesOverWhatIsBehind() {
        func screen(_ view: some View) -> [String] {
            var context = RenderContext(availableWidth: 4, availableHeight: 1, tuiContext: TUIContext())
                .isolatingRenderCache()
            context.environment.palette = SystemPalette.green
            return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines }
        }
        let material = screen(Text("ab").background(.thinMaterial).background(Color.red))
        #expect(material == screen(Text("ab").background(Color.palette.background.opacity(0.5)).background(Color.red)))
        #expect(material != screen(Text("ab").background(Color.palette.background).background(Color.red)), "not opaque")
        #expect(material != screen(Text("ab").background(Color.red)), "not absent")
    }

    @Test("View.materialActiveAppearance sets the environment below it")
    func viewModifier() {
        var seen: MaterialActiveAppearance?
        let context = RenderContext(availableWidth: 4, availableHeight: 1, tuiContext: TUIContext())
            .isolatingRenderCache()
        _ = renderToBuffer(
            AppearanceReader { seen = $0 }.materialActiveAppearance(.inactive), context: context)
        #expect(seen == .inactive)
        #expect(EnvironmentValues().materialActiveAppearance == .automatic)
        #expect(EnvironmentValues().backgroundMaterial == nil)
    }
}

/// `ShapeStyle.materialActiveAppearance(_:)` on a style whose static type is
/// not `Material`.
private enum ShapeStyleWrapperProbe {
    static func inactive(_ style: some ShapeStyle) -> some ShapeStyle {
        style.materialActiveAppearance(.inactive)
    }
}

/// An existential style, painted through its own witness.
private struct AnyShapeStyleBox: ShapeStyle {
    let base: any ShapeStyle
    init(_ base: any ShapeStyle) { self.base = base }
    typealias Resolved = Never
    func paint(in environment: EnvironmentValues) -> Paint { base.paint(in: environment) }
}

/// Hands `read` the materials' active appearance when it renders.
private struct AppearanceReader: View, Renderable {
    let read: (MaterialActiveAppearance) -> Void
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        read(context.environment.materialActiveAppearance)
        return FrameBuffer(text: "x")
    }
}
