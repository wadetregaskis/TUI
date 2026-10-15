//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSizeButtonTests.swift
//
//  A bordered button drawn at each ``ControlSize`` in each
//  ``ButtonBorderShape``: the density table of `ButtonFaceEdges.swift` — what
//  it draws, that it measures what it draws, and that a three-row face
//  breathes whole.
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
            (.large, ["▗▄▄▄▄▖", "▐ OK ▌", "▝▀▀▀▀▘"]),
            (.extraLarge, ["▗      ▖", "▐  OK  ▌", "▝      ▘"]),
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
            (.small, ["(OK)"]),
            (.regular, ["( OK )"]),
            (.large, ["╭────╮", "│ OK │", "╰────╯"]),
            (.extraLarge, ["╭──────╮", "│  OK  │", "╰──────╯"]),
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
        #expect(drawn(Button("★") {}.buttonBorderShape(.circle).controlSize(.extraLarge)) == ["▗ ▖", "▐★▌", "▝ ▘"])
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

    @Test(
        "A focused three-row face breathes whole, its label's row too",
        arguments: [false, true], [ControlSize.large, .extraLarge])
    func tallFaceBreathesWhole(viewLabel: Bool, size: ControlSize) {
        let context = makeRenderContext(width: 40, height: 6)
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size))
            : AnyView(Button("OK") {}.controlSize(size))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context) }
        let runs = buffer.animatedCells.map { ($0.offsetX, $0.offsetY, $0.width) }
        #expect(Set(buffer.animatedCells.map(\.offsetY)) == [0, 1, 2], "\(runs)")
        // Every row's run is the whole face, the label's field included: no
        // part of the face is left at rest while the rest breathes.
        #expect(buffer.animatedCells.allSatisfy { $0.offsetX == 0 && $0.width == buffer.width }, "\(runs)")
        // And each run's frames differ, so the label's field moves with the rows.
        let labelRow = buffer.animatedCells.first { $0.offsetY == 1 }
        #expect(Set(labelRow?.frames ?? []).count > 1)
    }

    @Test(
        "Where block elements fall short of the line, a three-row face has none",
        arguments: [ControlSize.large, .extraLarge], [false, true])
    func plainRowsWhereBlocksFallShort(size: ControlSize, viewLabel: Bool) {
        var context = context()
        context.environment.blockElementsFillTheLine = false
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size))
            : AnyView(Button("OK") {}.controlSize(size))
        let lines = renderToBuffer(button, context: context).lines
        let padding = size == .extraLarge ? "  " : " "
        #expect(lines.map(\.stripped) == [
            String(repeating: " ", count: 4 + 2 * padding.count), " \(padding)OK\(padding) ",
            String(repeating: " ", count: 4 + 2 * padding.count),
        ])
        #expect(!lines.joined().contains { ("\u{2580}"..."\u{259F}").contains($0) })
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

    @Test("A rounded rectangle has no field at any size, only lines", arguments: ControlSize.allCases, [false, true])
    func outlineHasNoField(size: ControlSize, viewLabel: Bool) {
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size).buttonBorderShape(.roundedRectangle))
            : AnyView(Button("OK") {}.controlSize(size).buttonBorderShape(.roundedRectangle))
        let lines = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context()).lines }
        // No background is painted anywhere: no SGR 48 (nor 49's explicit reset is needed).
        #expect(!lines.joined().contains("[48;"), "\(lines)")
    }

    @Test("A rounded rectangle's lines show at rest on every shipped palette, at 256 colours too")
    func outlineLinesShowAtRest() {
        for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
            let page = palette.background.resolve(with: palette)
            let ink = _ButtonStyleBody.outlineInk(palette: palette, surface: page, hovered: false, disabled: false)
            let ratio = ink.downsampledToPalette256().contrastRatio(against: page.downsampledToPalette256())
            #expect(ratio >= ViewConstants.buttonOutlineContrastFloor - 0.01, "\(palette.name): \(ratio)")
        }
    }

    @Test(
        "A focused rounded rectangle breathes its lines and its label together",
        arguments: [ControlSize.regular, .large], [false, true])
    func outlineBreathes(size: ControlSize, viewLabel: Bool) {
        let context = makeRenderContext(width: 40, height: 6)
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size).buttonBorderShape(.roundedRectangle))
            : AnyView(Button("OK") {}.controlSize(size).buttonBorderShape(.roundedRectangle))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context) }
        let runs = buffer.animatedCells.map { ($0.offsetX, $0.offsetY, $0.width) }
        #expect(Set(buffer.animatedCells.map(\.offsetY)) == Set(0..<buffer.height), "\(runs)")
        #expect(buffer.animatedCells.allSatisfy { $0.offsetX == 0 && $0.width == buffer.width }, "\(runs)")
    }

    @Test(
        "A rounded rectangle of radius zero is square",
        arguments: [
            (ControlSize.mini, ["OK"]),
            (.small, ["[OK]"]),
            (.regular, ["[ OK ]"]),
            (.large, ["┌────┐", "│ OK │", "└────┘"]),
            (.extraLarge, ["┌──────┐", "│  OK  │", "└──────┘"]),
        ])
    func square(size: ControlSize, expected: [String]) {
        for button in buttons(size, .roundedRectangle(radius: 0)) {
            #expect(drawn(button) == expected)
        }
    }

    @Test(
        "Brackets of your own draw the rounded rectangle's face between them",
        arguments: [
            (ControlSize.small, ["<OK>"]),
            (.regular, ["< OK >"]),
            (.large, ["╭────╮", "│ OK │", "╰────╯"]),
        ])
    func brackets(size: ControlSize, expected: [String]) {
        for button in buttons(size, .brackets("<", ">")) {
            #expect(drawn(button) == expected)
        }
    }

    @Test("Brackets wider than a cell draw as the rounded rectangle")
    func wideBrackets() {
        #expect(drawn(Button("OK") {}.buttonBorderShape(.brackets("中", "中"))) == ["( OK )"])
        #expect(drawn(Button("OK") {}.buttonBorderShape(.brackets("⟨", "⟩"))) == ["⟨ OK ⟩"])
    }
}
