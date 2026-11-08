//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometricArrowFocusTests.swift
//
//  `TUI_ARROW_FOCUS=geometric`: an arrow the focused control leaves unused goes
//  to the nearest control on screen in its direction — inside the beam first,
//  then the nearer, then the earlier in Tab order — and in Tab order where
//  there is none, without leaving the active section or a sheet. And the
//  default, Tab order, as it was.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("Geometric arrow focus")
struct GeometricArrowFocusTests {
    /// Three rows of three buttons, `r0c0` … `r2c2`, in reading (Tab) order.
    private struct Grid: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { column in
                            Button("r\(row)c\(column)") {}.focusID("r\(row)c\(column)")
                        }
                    }
                }
            }
        }
    }

    /// The same nine buttons as three columns, so Tab goes down each column.
    private struct ColumnGrid: View {
        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(0..<3, id: \.self) { row in
                            Button("r\(row)c\(column)") {}.focusID("r\(row)c\(column)")
                        }
                    }
                }
            }
        }
    }

    private static let gridIDs: Set<String> = Set((0..<3).flatMap { row in (0..<3).map { "r\(row)c\($0)" } })

    private func app<Content: View>(
        _ arrows: ArrowFocus, @ViewBuilder _ content: @escaping () -> Content
    ) -> TestApp {
        let app = TestApp(content: content)
        app.arrowFocus = arrows
        return app
    }

    /// The focus ids `key` visits, pressed `times` times, the start included.
    private func visits(_ app: TestApp, _ key: Key, times: Int) -> [String] {
        var seen = [app.focusedID ?? "nil"]
        for _ in 0..<times {
            app.press(key)
            seen.append(app.focusedID ?? "nil")
        }
        return seen
    }

    @Test("Only `geometric` says anything")
    func variable() {
        #expect(ArrowFocus.requested(environment: ["TUI_ARROW_FOCUS": "geometric"]) == .geometric)
        #expect(ArrowFocus.requested(environment: ["TUI_ARROW_FOCUS": "1"]) == .tabOrder)
        #expect(ArrowFocus.requested(environment: [:]) == .tabOrder)
    }

    @Test("Down goes to the button below, not the next in Tab order")
    func gridDown() {
        let geometric = app(.geometric) { Grid() }
        #expect(geometric.focusedID == "r0c0")
        #expect(visits(geometric, .down, times: 2) == ["r0c0", "r1c0", "r2c0"])
        geometric.press(.right)
        geometric.press(.up)
        #expect(geometric.focusedID == "r1c1")
        geometric.press(.left)
        #expect(geometric.focusedID == "r1c0")
    }

    @Test("The default is Tab order, and keeps no frames")
    func defaultIsTabOrder() {
        let plain = TestApp { Grid() }
        #expect(plain.arrowFocus == .tabOrder)
        #expect(visits(plain, .down, times: 3) == ["r0c0", "r0c1", "r0c2", "r1c0"])
        #expect(visits(plain, .up, times: 1) == ["r1c0", "r0c2"])
        #expect(plain.services.mouseEventDispatcher.regions.contains { $0.focusID == "r0c0" })
        #expect(plain.laidOutRegions.isEmpty)
    }

    @Test("Where nothing lies that way, the arrow falls back to Tab order, and stops at the end as it does today")
    func fallback() {
        let geometric = app(.geometric) { Grid() }
        geometric.press(.down, times: 2)
        #expect(visits(geometric, .down, times: 3) == ["r2c0", "r2c1", "r2c2", "r2c2"])
        // Up from the top row has nothing above: back in Tab order.
        let again = app(.geometric) { Grid() }
        again.press(.right)
        #expect(visits(again, .up, times: 1) == ["r0c1", "r0c0"])
    }

    @Test("Every control is reachable: repeated Right in reading order, repeated Down in column order")
    func reachable() {
        let rows = app(.geometric) { Grid() }
        #expect(Set(visits(rows, .right, times: 8)) == Self.gridIDs)
        let columns = app(.geometric) { ColumnGrid() }
        #expect(Set(visits(columns, .down, times: 8)) == Self.gridIDs)
        // Repeated Down in reading order walks the first column and then the
        // last row (the Tab-order fallback): not every control. Mixing the
        // arrows reaches them all.
        let mixed = app(.geometric) { Grid() }
        #expect(Set(visits(mixed, .down, times: 8)) == ["r0c0", "r1c0", "r2c0", "r2c1", "r2c2"])
    }

    /// `top` sits to the right; `near` is the next row down but outside its
    /// columns; `far` is two rows further, inside them.
    private struct Beam: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Button("top") {}.focusID("top").padding(.leading, 30)
                Button("near") {}.focusID("near")
                Button("far") {}.focusID("far").padding(.leading, 31)
            }
        }
    }

    @Test("Inside the beam beats nearer outside it")
    func beamFirst() {
        let geometric = app(.geometric) { Beam() }
        #expect(visits(geometric, .down, times: 1) == ["top", "far"])
    }

    /// From `top`, neither of the two below overlaps its columns: `left` is a
    /// row nearer but far to the side, `right` a row further but close.
    private struct Distance: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Button("top") {}.focusID("top").padding(.leading, 30)
                Button("left") {}.focusID("left")
                Text(" ")
                Button("right") {}.focusID("right").padding(.leading, 42)
            }
        }
    }

    @Test("Outside the beam, the nearer wins, a row counting as two columns")
    func distance() {
        let geometric = app(.geometric) { Distance() }
        #expect(visits(geometric, .down, times: 1) == ["top", "right"])
    }

    /// Two buttons the same distance above a wide one, both inside its beam.
    private struct Tie: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Button("one") {}.focusID("one")
                    Button("two") {}.focusID("two")
                }
                Button("a wide button under both of them") {}.focusID("wide")
            }
        }
    }

    @Test("A tie goes to the earlier in Tab order, every time, not the previous in Tab order")
    func tie() {
        for _ in 0..<3 {
            let geometric = app(.geometric) { Tie() }
            geometric.press(.tab, times: 2)
            #expect(visits(geometric, .up, times: 1) == ["wide", "one"])
        }
    }

    /// Two sections side by side: arrows do not cross from one to the other.
    private struct Sections: View {
        var body: some View {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Button("a one") {}.focusID("a-one")
                    Button("a two") {}.focusID("a-two")
                }
                .focusSection("a")
                VStack(alignment: .leading, spacing: 1) {
                    Button("b one") {}.focusID("b-one")
                    Button("b two") {}.focusID("b-two")
                }
                .focusSection("b")
            }
        }
    }

    @Test("Arrows stay in the active section: Right from a section's control falls back inside it")
    func sections() {
        let geometric = app(.geometric) { Sections() }
        #expect(visits(geometric, .right, times: 1) == ["a-one", "a-two"])
        #expect(visits(geometric, .up, times: 1) == ["a-two", "a-one"])
    }

    /// A page of buttons under a sheet of two.
    private struct SheetPage: View {
        @State private var presented = true

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Grid()
            }
            .sheet(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 1) {
                    Button("sheet one") {}.focusID("s-one")
                    Button("sheet two") {}.focusID("s-two")
                }
            }
        }
    }

    @Test("A sheet keeps the arrows: nothing on the page beneath is a candidate")
    func sheet() {
        let geometric = app(.geometric) { SheetPage() }
        #expect(visits(geometric, .down, times: 1) == ["s-one", "s-two"])
        // On past the sheet's last control, into its own stops if any, but
        // never onto the page.
        let onward = visits(geometric, .down, times: 4) + visits(geometric, .right, times: 4)
        #expect(Self.gridIDs.isDisjoint(with: onward))
    }
}
