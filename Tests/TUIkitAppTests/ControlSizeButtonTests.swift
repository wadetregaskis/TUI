//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSizeButtonTests.swift
//
//  A bordered button drawn at each ``ControlSize`` in each
//  ``ButtonBorderShape``: the density table of `ButtonFaceEdges.swift` — what
//  it draws, that it measures what it draws, and that a three-row face's ring
//  breathes with its caps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Control sizes and border shapes")
struct ControlSizeButtonTests {
    private func context(width: Int = 40) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: 6, environment: environment, tuiContext: tui)
    }

    private func drawn(_ view: some View, width: Int = 40) -> [String] {
        renderToBuffer(view, context: context(width: width)).lines.map(\.stripped)
    }

    /// A string label and a `@ViewBuilder` one, which take different paths
    /// through the style and must draw alike.
    private func buttons(_ size: ControlSize, _ shape: ButtonBorderShape) -> [AnyView] {
        [
            AnyView(Button("OK") {}.controlSize(size).buttonBorderShape(shape)),
            AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size).buttonBorderShape(shape)),
        ]
    }

    @Test(
        "A bordered button at each size, as a capsule",
        arguments: [
            (ControlSize.mini, ["OK"]),
            (.small, ["▐OK▌"]),
            (.regular, ["▐ OK ▌"]),
            (.large, [" ▄▄▄▄ ", "▐ OK ▌", " ▀▀▀▀ "]),
            (.extraLarge, [" ▄▄▄▄▄▄ ", "▐  OK  ▌", " ▀▀▀▀▀▀ "]),
        ])
    func capsule(size: ControlSize, expected: [String]) {
        for button in buttons(size, .automatic) {
            #expect(drawn(button) == expected)
        }
        for button in buttons(size, .capsule) {
            #expect(drawn(button) == expected)
        }
    }

    @Test(
        "A bordered button at each size, as a rounded rectangle",
        arguments: [
            (ControlSize.mini, ["OK"]),
            (.small, ["▕OK▏"]),
            (.regular, ["▕ OK ▏"]),
            (.large, ["▗▄▄▄▄▖", "▐ OK ▌", "▝▀▀▀▀▘"]),
            (.extraLarge, ["▗▄▄▄▄▄▄▖", "▐  OK  ▌", "▝▀▀▀▀▀▀▘"]),
        ])
    func roundedRectangle(size: ControlSize, expected: [String]) {
        for button in buttons(size, .roundedRectangle) {
            #expect(drawn(button) == expected)
        }
        for button in buttons(size, .roundedRectangle(radius: 4)) {
            #expect(drawn(button) == expected)
        }
    }

    @Test("A circle has no padding at any size")
    func circle() {
        #expect(drawn(Button("★") {}.buttonBorderShape(.circle)) == ["▐★▌"])
        #expect(drawn(Button("★") {}.buttonBorderShape(.circle).controlSize(.extraLarge)) == [" ▄ ", "▐★▌", " ▀ "])
    }

    @Test("A button with no face draws as it would at any size", arguments: ControlSize.allCases)
    func faceless(size: ControlSize) {
        for style in [ButtonStyleCase.plain] {
            let regular = drawn(style.apply(to: Button("OK") {}))
            #expect(drawn(style.apply(to: Button("OK") {}).controlSize(size)) == regular)
        }
        #expect(drawn(Button("OK") {}.buttonStyle(.borderless).controlSize(size)) == drawn(Button("OK") {}.buttonStyle(.borderless)))
    }

    @Test(
        "The measured size is the drawn size at every size",
        arguments: ControlSize.allCases, [ButtonBorderShape.automatic, .roundedRectangle, .circle])
    func measuredEqualsDrawn(size: ControlSize, shape: ButtonBorderShape) {
        for style in [ButtonStyleCase.default, .primary, .destructive, .plain] {
            for label in ["OK", "A rather longer label"] {
                // From the widest chrome (`.extraLarge`'s six cells) up: below
                // it the drawing is clamped to the offer and the measure is not,
                // at every size, as `ButtonMeasureParityTests` leaves it.
                for width in [6, 8, 40] {
                    let views = [
                        AnyView(style.apply(to: Button(label) {}).controlSize(size).buttonBorderShape(shape)),
                        AnyView(
                            style.apply(to: Button(action: {}, label: { Text(label) })).controlSize(size)
                                .buttonBorderShape(shape)),
                    ]
                    for view in views {
                        let rendered = renderToBuffer(view, context: context(width: width))
                        let measured = measureChild(view, proposal: .unspecified, context: context(width: width))
                        #expect(
                            measured.width == rendered.width && measured.height == rendered.height,
                            """
                            \(style) \(size) \(shape.kind) \(label) at \(width): \
                            measured \(measured.width)×\(measured.height), drew \(rendered.width)×\(rendered.height)
                            """)
                    }
                }
            }
        }
    }

    @Test("The range form holds the size in force within it")
    func rangeForm() {
        #expect(ControlSize.clamping(.mini, to: ControlSize.small ... .large) == .small)
        #expect(ControlSize.clamping(.regular, to: ControlSize.small ... .large) == .regular)
        #expect(ControlSize.clamping(.extraLarge, to: ControlSize.small ... .large) == .large)
        #expect(ControlSize.clamping(.mini, to: ControlSize.large...) == .large)
        #expect(ControlSize.clamping(.extraLarge, to: ..<ControlSize.regular) == .small)
        #expect(ControlSize.clamping(.large, to: ControlSize.regular ..< .regular) == .large, "an empty range holds nothing")
        #expect(
            drawn(Button("OK") {}.controlSize(ControlSize.small ... .large).controlSize(.mini)) == ["▐OK▌"])
        #expect(
            drawn(Button("OK") {}.controlSize(ControlSize.small ... .large)) == ["▐ OK ▌"])
    }

    @Test("A focused three-row face breathes its ring with its caps", arguments: [false, true])
    func ringBreathes(viewLabel: Bool) {
        let context = makeRenderContext(width: 40, height: 6)
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(.large))
            : AnyView(Button("OK") {}.controlSize(.large))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context) }
        let rows = Set(buffer.animatedCells.map(\.offsetY))
        #expect(rows == [0, 1, 2], "\(buffer.animatedCells.map { ($0.offsetX, $0.offsetY, $0.width) })")
        let ring = buffer.animatedCells.filter { $0.offsetY != 1 }
        #expect(ring.allSatisfy { $0.offsetX == 0 && $0.width == 6 })
    }

    @Test("A focused mini face breathes its label", arguments: [false, true])
    func miniBreathes(viewLabel: Bool) {
        let context = makeRenderContext(width: 40, height: 6)
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(.mini))
            : AnyView(Button("OK") {}.controlSize(.mini))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context) }
        #expect(!buffer.animatedCells.isEmpty)
        #expect(buffer.animatedCells.allSatisfy { $0.offsetY == 0 && $0.width == 2 })
    }
}
