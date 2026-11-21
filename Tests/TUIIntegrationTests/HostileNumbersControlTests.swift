//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersControlTests.swift
//
//  Progress views, gauges, sliders, steppers, tables and formatted text
//  handed hostile values, bounds and steps: each must draw, and take a key,
//  without trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICurveEditors
@testable import TUIFoundation
@testable import TUITables
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: controls")
struct HostileNumbersControlTests {

    /// Draws `view` at every hostile size, pressing each of `keys` between
    /// frames — a control's step is only taken when a key moves it.
    private func drawPressing<V: View>(_ view: @autoclosure () -> V) {
        let keys: [Key] = [.right, .left, .up, .down, .end, .home, .pageUp, .pageDown]
        for size in Hostile.sizes {
            let harness = InputChainHarness(width: size.width, height: size.height)
            harness.frame(view())
            for key in keys {
                harness.press(KeyEvent(key: key))
                harness.frame(view())
            }
        }
    }

    @Test("A progress view of any value or total draws", arguments: Hostile.doubles)
    func progress(value: Double) {
        drawHostile(ProgressView(value: value))
        drawHostile(ProgressView(value: 0.5, total: value))
        drawHostile(ProgressView(value: value, total: value))
        drawHostile(ProgressView(value: value) { Text("Loading") })
        drawHostile(ProgressView(value: Float(value), total: 1))
    }

    @Test("A gauge of any value draws", arguments: Hostile.doubles)
    func gauge(value: Double) {
        drawHostile(Gauge(value: value) { Text("g") })
        drawHostile(Gauge(value: value, in: 0...10) { Text("g") })
        if !value.isNaN {
            drawHostile(Gauge(value: 1, in: value...value) { Text("g") })
            drawHostile(Gauge(value: 0.5, in: min(value, 0)...max(value, 0)) { Text("g") })
        }
    }

    @Test("A slider of any value, bounds or step draws and moves", arguments: Hostile.doubles)
    func slider(value: Double) {
        drawPressing(Slider(value: .constant(value), in: 0...1))
        drawPressing(Slider(value: .constant(0.5), in: 0...1, step: value))
        drawPressing(Slider(value: .constant(value), in: 0...1, step: value))
        if !value.isNaN {
            drawPressing(Slider(value: .constant(0.5), in: min(value, 0)...max(value, 0)))
            drawPressing(Slider(value: .constant(value), in: value...value))
        }
        var stored = value
        let binding = Binding(get: { stored }, set: { stored = $0 })
        drawPressing(Slider(value: binding, in: 0...1, step: 0.1))
    }

    @Test("A floating-point stepper of any value, bounds or step draws and moves", arguments: Hostile.doubles)
    func doubleStepper(value: Double) {
        var stored = value
        let binding = Binding(get: { stored }, set: { stored = $0 })
        drawPressing(Stepper("s", value: binding, step: 1))
        drawPressing(Stepper("s", value: binding, in: 0...10, step: 1))
        drawPressing(Stepper("s", value: .constant(1.0), step: value))
        drawPressing(Stepper("s", value: .constant(1.0), in: 0...10, step: value))
        if !value.isNaN {
            drawPressing(Stepper("s", value: binding, in: min(value, 0)...max(value, 0), step: 1))
        }
    }

    @Test("An integer stepper of any value, bounds or step draws and moves", arguments: Hostile.ints)
    func intStepper(value: Int) {
        var stored = value
        let binding = Binding(get: { stored }, set: { stored = $0 })
        drawPressing(Stepper("s", value: binding, step: 1))
        drawPressing(Stepper("s", value: binding, in: 0...10))
        drawPressing(Stepper("s", value: .constant(1), step: value))
        drawPressing(Stepper("s", value: .constant(1), in: 0...10, step: value))
        drawPressing(Stepper("s", value: binding, in: min(value, 0)...max(value, 0)))
        drawPressing(Stepper("s", value: binding, in: Int.min...Int.max, step: value))
    }

    @Test("Text formatting any number draws", arguments: Hostile.doubles)
    func formattedText(value: Double) {
        drawHostile(Text(value, format: .number))
        drawHostile(Text(value, format: .percent))
        drawHostile(Text(value, format: .number.precision(.fractionLength(2))))
        drawHostile(Text("\(value)"))
    }

    @Test("A table column of any width draws", arguments: Hostile.ints)
    func tableWidths(width: Int) {
        struct Row: Identifiable {
            let id: Int
            let name: String
        }
        let rows = [Row(id: 0, name: "zero"), Row(id: 1, name: "one")]
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name).width(width) })
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name).width(min: width, ideal: width, max: width) })
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name).width(min: width) })
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name).width(max: width) })
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name).lineLimit(width) })
        drawHostile(Table(rows) { TableColumn("Name", value: \Row.name) }.tableColumnSpacing(width))
    }

    @Test("A grid of any spacing or column size draws", arguments: Hostile.ints)
    func grids(value: Int) {
        drawHostile(
            Grid(horizontalSpacing: value, verticalSpacing: value) {
                GridRow { Text("a"); Text("b") }
                GridRow { Text("c").gridCellColumns(2) }
            })
        // A span is as many columns, each a gap apart: a huge span AND a huge
        // gap is a picture as wide as their product — the two-axis case of
        // HostileNumbersSupport.swift — so each is huge on its own.
        drawHostile(
            Grid {
                GridRow { Text("a"); Text("b") }
                GridRow { Text("c").gridCellColumns(value) }
            })
        for size: GridItem.Size in [
            .fixed(value), .flexible(minimum: value, maximum: value), .adaptive(minimum: value),
            .adaptive(minimum: 1, maximum: value),
        ] {
            drawHostile(
                LazyVGrid(columns: [GridItem(size, spacing: value)], spacing: value) {
                    ForEach(0..<6, id: \.self) { Text("\($0)") }
                })
            drawHostile(
                LazyHGrid(rows: [GridItem(size)], spacing: value) {
                    ForEach(0..<6, id: \.self) { Text("\($0)") }
                })
        }
    }

    // MARK: Hunt 11-20
    //
    // Each of these trapped before its fix, which ends the whole run; so each
    // runs in a child process, where a trap is this test's recorded failure.

    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        @Test("A curve editor over points at NaN, infinity or 1e308 draws, its read-outs held to 0...100% (CTRLS-3)")
        func curveEditors() async {
            await #expect(processExitsWith: .success) { await MainActor.run { ControlTraps.curveEditors() } }
        }

        @Test("An indeterminate bar of any extent draws (sweep)")
        func indeterminateExtent() async {
            await #expect(processExitsWith: .success) { await MainActor.run { ControlTraps.indeterminateExtent() } }
        }

        @Test("A table customization decoded with any width draws (TABLES-7)")
        func decodedColumnWidths() async {
            await #expect(processExitsWith: .success) { await MainActor.run { ControlTraps.decodedColumnWidths() } }
        }
    #endif
}

/// The hostile-number checks the control suite runs in child processes.
@MainActor
private enum ControlTraps {
    static let values: [Double] = Hostile.doubles + [1e308, -1e308, .greatestFiniteMagnitude]

    static func curveEditors() {
        typealias Point = ASCIIToneCurve.Ramp.Point
        for value in values {
            // A point whose input is hostile dies in the marker row; one whose
            // output is, in the selected point's read-out (point 0 is selected
            // as the editor opens).
            let ramp = ASCIIToneCurve.Ramp([Point(input: value, output: value), Point(input: 1, output: 1)])
            let channels = ASCIIToneCurve.Channels(red: ramp, green: ramp, blue: ramp)
            drawHostile(ChannelCurveEditorPanel("Curves", channels: .constant(channels), isPresented: .constant(true)))
            let stops = [ASCIIToneCurve.Stop(at: value, to: .white), ASCIIToneCurve.Stop(at: 1, to: .black)]
            drawHostile(ToneCurveEditorPanel("Tone", stops: .constant(stops), isPresented: .constant(true)))
            _ = ASCIIToneCurve.Stop(at: value, to: .gray)
            _ = ASCIIToneCurve(stops).color(atTone: value)
            let percent = ChannelCurveEditorPanel.percent(value)
            precondition((0...100).contains(percent), "\(value) read \(percent)%")
        }
        precondition(ChannelCurveEditorPanel.percent(1e308) == 100 && ChannelCurveEditorPanel.percent(.nan) == 0)
        precondition(ChannelCurveEditorPanel.percent(0.505) == 51)
    }

    static func indeterminateExtent() {
        for value in values {
            let configuration = IndeterminateConfiguration(motion: .sweep, period: 1, extent: value)
            drawHostile(ProgressView().indeterminateStyle(.custom(configuration)))
            var changed = IndeterminateConfiguration.sweep
            changed.extent = value
            drawHostile(ProgressView().indeterminateStyle(.custom(changed)))
        }
    }

    struct Row: Identifiable {
        let id: Int
        let name: String
        let size: String
    }

    static func decodedColumnWidths() {
        let rows = [Row(id: 0, name: "zero", size: "1"), Row(id: 1, name: "one", size: "2")]
        for width in [Int.max, 1_000_000_000_000, 65_537] {
            let json = Data(#"{"width": {"name": \#(width), "size": \#(width)}}"#.utf8)
            guard let decoded = try? JSONDecoder().decode(TableColumnCustomization<Row>.self, from: json) else {
                preconditionFailure("the customization decodes")
            }
            precondition(decoded[width: "name"] == Int.statedLengthLimit, "held as a stated width")
            drawHostile(
                Table(rows, columnCustomization: .constant(decoded)) {
                    TableColumn("Name", value: \Row.name).customizationID("name")
                    TableColumn("Size", value: \Row.size).customizationID("size")
                })
        }
    }
}
