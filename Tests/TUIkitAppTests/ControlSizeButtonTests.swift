//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSizeButtonTests.swift
//
//  A bordered button drawn at each ``ControlSize`` in each
//  ``ButtonBorderShape``: the density table of `ButtonFaceEdges.swift` — what
//  it draws in each family of the ``Appearance`` in force, that it
//  measures what it draws, and how each family breathes the focus.
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
    private func buttons(
        _ size: ControlSize, _ shape: ButtonBorderShape, _ appearance: Appearance = .rounded, label: String = "OK"
    ) -> [AnyView] {
        [
            AnyView(Button(label) {}.controlSize(size).buttonBorderShape(shape).appearance(appearance)),
            AnyView(
                Button(action: {}, label: { Text(label) }).controlSize(size).buttonBorderShape(shape)
                    .appearance(appearance)),
        ]
    }

    @Test(
        "A bordered button at each size, as a capsule in lines (the default)",
        arguments: [
            (ControlSize.mini, ["OK"]),
            (.small, ["(OK)"]),
            (.regular, ["( OK )"]),
            (.large, ["╭────╮", "( OK )", "╰────╯"]),
            (.extraLarge, ["╭──────╮", "(  OK  )", "╰──────╯"]),
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
            (.small, ["│OK│"]),
            (.regular, ["│ OK │"]),
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

    @Test("A circle has no padding on one row, and on three is about as wide as it is tall")
    func circle() {
        for button in buttons(.regular, .circle, label: "★") { #expect(drawn(button) == ["(★)"]) }
        for button in buttons(.extraLarge, .circle, label: "★") {
            #expect(drawn(button) == ["╭───╮", "( ★ )", "╰───╯"])
        }
        for button in buttons(.regular, .circle, .block, label: "★") { #expect(drawn(button) == ["▐★▌"]) }
        for button in buttons(.extraLarge, .circle, .block, label: "★") {
            #expect(drawn(button) == ["▗▟   ▙▖", "   ★   ", "▝▜   ▛▘"])
        }
    }

    @Test(
        "The solid family: filled faces, the shape drawn in quadrants on three rows",
        arguments: [
            (ControlSize.mini, ButtonBorderShape.capsule, ["OK"]),
            (.small, .capsule, ["▐OK▌"]),
            (.regular, .capsule, ["▐ OK ▌"]),
            (.large, .capsule, ["▗▟  ▙▖", "  OK  ", "▝▜  ▛▘"]),
            (.extraLarge, .capsule, ["▗▟    ▙▖", "   OK   ", "▝▜    ▛▘"]),
            (.regular, .roundedRectangle, ["  OK  "]),
            (.large, .roundedRectangle, ["▟    ▙", "  OK  ", "▜    ▛"]),
            (.large, .roundedRectangle(radius: 0), ["      ", "  OK  ", "      "]),
        ])
    func solid(size: ControlSize, shape: ButtonBorderShape, expected: [String]) {
        for button in buttons(size, shape, .block) {
            #expect(drawn(button) == expected)
        }
    }

    @Test(
        "A lines face takes the appearance's own border glyphs",
        arguments: [
            (Appearance.line, ButtonBorderShape.roundedRectangle, ["┌────┐", "│ OK │", "└────┘"]),
            (.heavy, .roundedRectangle, ["┏━━━━┓", "┃ OK ┃", "┗━━━━┛"]),
            (.heavy, .capsule, ["┏━━━━┓", "( OK )", "┗━━━━┛"]),
            (.doubleLine, .roundedRectangle, ["╔════╗", "║ OK ║", "╚════╝"]),
        ])
    func linesTakeTheBorder(appearance: Appearance, shape: ButtonBorderShape, expected: [String]) {
        for button in buttons(.large, shape, appearance) {
            #expect(drawn(button) == expected)
        }
    }

    @Test("Under the blank appearance a button is its label", arguments: ControlSize.allCases)
    func blank(size: ControlSize) {
        for button in buttons(size, .capsule, .blank) {
            #expect(drawn(button).map { $0.filter { $0 != " " } } == ["OK"])
        }
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
        "The measured size is the drawn size at every size, in every family",
        arguments: ControlSize.allCases, [ButtonBorderShape.automatic, .roundedRectangle, .circle])
    func measuredEqualsDrawn(size: ControlSize, shape: ButtonBorderShape) {
        for appearance in [Appearance.rounded, .block, .blank] {
            measuredEqualsDrawn(size: size, shape: shape, appearance: appearance)
        }
    }

    private func measuredEqualsDrawn(size: ControlSize, shape: ButtonBorderShape, appearance: Appearance) {
        for style in [ButtonStyleCase.default, .primary, .destructive, .plain] {
            for label in ["OK", "A rather longer label"] {
                // From the widest chrome (`.extraLarge`'s six cells) up: below
                // it the drawing is clamped to the offer and the measure is not,
                // at every size, as `ButtonMeasureParityTests` leaves it.
                for width in [6, 8, 40] {
                    let views = [
                        AnyView(
                            style.apply(to: Button(label) {}).controlSize(size).buttonBorderShape(shape)
                                .appearance(appearance)),
                        AnyView(
                            style.apply(to: Button(action: {}, label: { Text(label) })).controlSize(size)
                                .buttonBorderShape(shape).appearance(appearance)),
                    ]
                    for view in views {
                        let rendered = renderToBuffer(view, context: context(width: width))
                        let measured = measureChild(view, proposal: .unspecified, context: context(width: width))
                        #expect(
                            measured.width == rendered.width && measured.height == rendered.height,
                            """
                            \(appearance.id) \(style) \(size) \(shape.kind) \(label) at \(width): \
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
            drawn(Button("OK") {}.controlSize(ControlSize.small ... .large).controlSize(.mini)) == ["(OK)"])
        #expect(
            drawn(Button("OK") {}.controlSize(ControlSize.small ... .large)) == ["( OK )"])
    }

    @Test(
        "A focused solid face drawn whole breathes whole, its label's row too",
        arguments: [false, true], [ControlSize.large, .extraLarge, .regular])
    func tallFaceBreathesWhole(viewLabel: Bool, size: ControlSize) {
        let context = makeRenderContext(width: 40, height: 6)
        // A three-row face, or a one-row rectangle with square ends.
        let shape: ButtonBorderShape = size == .regular ? .roundedRectangle : .capsule
        let button = viewLabel
            ? AnyView(
                Button(action: {}, label: { Text("OK") }).controlSize(size).buttonBorderShape(shape)
                    .appearance(.block))
            : AnyView(Button("OK") {}.controlSize(size).buttonBorderShape(shape).appearance(.block))
        let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(button, context: context) }
        let runs = buffer.animatedCells.map { ($0.offsetX, $0.offsetY, $0.width) }
        #expect(Set(buffer.animatedCells.map(\.offsetY)) == Set(0..<buffer.height), "\(runs)")
        // Every row's run is the whole face, the label's field included: no
        // part of the face is left at rest while the rest breathes.
        #expect(buffer.animatedCells.allSatisfy { $0.offsetX == 0 && $0.width == buffer.width }, "\(runs)")
        // And each run's frames differ, so the label's field moves with the rows.
        let labelRow = buffer.animatedCells.first { $0.offsetY == buffer.height / 2 }
        #expect(Set(labelRow?.frames ?? []).count > 1)
    }

    @Test(
        "Where block elements fall short of the line, a three-row solid face has none",
        arguments: [ControlSize.large, .extraLarge], [false, true])
    func plainRowsWhereBlocksFallShort(size: ControlSize, viewLabel: Bool) {
        var context = context()
        context.environment.blockElementsFillTheLine = false
        let button = viewLabel
            ? AnyView(Button(action: {}, label: { Text("OK") }).controlSize(size).appearance(.block))
            : AnyView(Button("OK") {}.controlSize(size).appearance(.block))
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
        #expect(drawn(Button("OK") {}.buttonBorderShape(.brackets("中", "中"))) == ["│ OK │"])
        #expect(drawn(Button("OK") {}.buttonBorderShape(.brackets("⟨", "⟩"))) == ["⟨ OK ⟩"])
    }

    @Test(
        "An underline is the label alone on one row, and the rounded rectangle's box on three",
        arguments: [
            (ControlSize.mini, ["OK"]),
            (.small, ["OK"]),
            (.regular, [" OK "]),
            (.large, ["╭────╮", "│ OK │", "╰────╯"]),
        ])
    func underline(size: ControlSize, expected: [String]) {
        for button in buttons(size, .underline) {
            #expect(drawn(button) == expected)
        }
    }

    @Test("The underline is under the label, not its padding, in the lines' colour where the terminal colours one")
    func underlineSpansTheLabel() {
        func bytes(_ view: some View, support: LineStyleSupport) -> String {
            var context = context()
            context.environment.lineStyleSupport = support
            return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context).lines.joined() }
        }
        for button in buttons(.regular, .underline, label: "Save") {
            let coloured = bytes(button, support: .underlines)
            // One underlined run, and it is the label's cells exactly: the
            // padding either side is drawn bare.
            let underlinedRuns = coloured.components(separatedBy: "\u{1B}[").filter {
                $0.hasPrefix("4;") || $0.contains(";4;") || $0.hasPrefix("1;4;")
            }
            #expect(underlinedRuns.count == 1, "\(coloured.debugDescription)")
            #expect(underlinedRuns.first?.hasSuffix("mSave") == true, "\(coloured.debugDescription)")
            #expect(coloured.contains("58:"), "the line in the lines' colour: \(coloured.debugDescription)")
            let plain = bytes(button, support: .plain)
            #expect(!plain.contains("58") && plain.contains("Save"), "\(plain.debugDescription)")
        }
    }

    @Test(
        "The braille family: a dotted outline of the shape, one dot thick or two",
        arguments: [
            (Appearance.braille, ControlSize.regular, ButtonBorderShape.capsule, ["⢎ OK ⡱"]),
            (.braille, .large, .capsule, ["⢠⠒⠉⠉⠒⡄", "⡇ OK ⢸", "⠘⠤⣀⣀⠤⠃"]),
            (.braille, .regular, .roundedRectangle, ["⣏ OK ⣹"]),
            (.braille, .large, .roundedRectangle, ["⡎⠉⠉⠉⠉⢱", "⡇ OK ⢸", "⢇⣀⣀⣀⣀⡸"]),
            (.braille, .large, .roundedRectangle(radius: 0), ["⡏⠉⠉⠉⠉⢹", "⡇ OK ⢸", "⣇⣀⣀⣀⣀⣸"]),
            (.braille(thickness: 2), .regular, .capsule, ["⢾ OK ⡷"]),
            (.braille(thickness: 2), .large, .capsule, ["⢠⡶⠛⠛⢶⡄", "⣿ OK ⣿", "⠘⠷⣤⣤⠾⠃"]),
        ])
    func braille(appearance: Appearance, size: ControlSize, shape: ButtonBorderShape, expected: [String]) {
        for button in buttons(size, shape, appearance) {
            #expect(drawn(button) == expected)
        }
    }

    @Test("A braille circle is a dotted disc, about as wide as it is tall")
    func brailleCircle() {
        for button in buttons(.large, .circle, .braille, label: "★") {
            #expect(drawn(button) == ["⢠⠒⠉⠉⠉⠒⡄", "⡇  ★  ⢸", "⠘⠤⣀⣀⣀⠤⠃"])
        }
    }

    @Test("A braille box draws its four sides in their own dots", arguments: [1, 2])
    func brailleBox(thickness: Int) {
        let box = drawn(Text("Hi").border().appearance(.braille(thickness: thickness)))
        let expected =
            thickness == 1
            ? ["⡏⠉⠉⠉⠉⢹", "⡇ Hi ⢸", "⣇⣀⣀⣀⣀⣸"]
            : ["⣿⠛⠛⠛⠛⣿", "⣿ Hi ⣿", "⣿⣤⣤⣤⣤⣿"]
        #expect(box == expected)
    }

    @Test("A braille thickness is held to what a cell's dots can draw")
    func brailleThicknessHeld() {
        #expect(BorderStyle.braille(thickness: 0).brailleThickness == 1)
        #expect(BorderStyle.braille(thickness: 9).brailleThickness == 4)
        #expect(BorderStyle.braille(thickness: 4).vertical == "⣿", "a wall is at most a cell's two columns")
        #expect(Appearance.braille(thickness: 1) == .braille)
        #expect(Appearance.braille(thickness: 2).id == "braille2")
    }
}
