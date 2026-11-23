//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackEdgeWalkCostTests.swift
//
//  What the walk made before the key costs (LAZY-EDGE, deviation L7; owner,
//  2026-11-18: "(b)"). Where the focus stands beside a lazy stack whose rows on
//  screen have nothing to focus, and Tab or Shift-Tab from it would pass over
//  the stack, the frame walks the stack in from that edge, so the key goes
//  straight to the row found. Every row of a stack with nothing to focus is
//  walked, once, until the rows' data changes; a row found is asked again
//  alone. These pin that it is once.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITesting

/// The rows' data, changed from outside any render.
@MainActor @Observable
private final class WalkCostModel {
    var generation = 0
}

/// Counts row bodies built.
@MainActor
private final class RowBuilds {
    var count = 0
}

@MainActor
@Suite("Tab into a lazy stack: the walk before the key is made once per data", .serialized)
struct LazyStackEdgeWalkCostTests {
    private struct Row: View {
        let index: Int
        let button: Int?
        let builds: RowBuilds
        var body: some View {
            builds.count += 1
            return Group {
                if index == button {
                    Button("b\(index)") {}.focusID("b\(index)")
                } else {
                    Text("x\(index)")
                }
            }
        }
    }

    private struct Page: View {
        let builds: RowBuilds
        let rows: Int
        let button: Int?
        let generation: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}.focusID("top")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(generation..<(generation + rows), id: \.self) {
                            Row(index: $0 - generation, button: button, builds: builds)
                        }
                    }
                }
                .frame(height: 6)
                Button("bottom") {}.focusID("bottom")
            }
        }
    }

    /// A page's app and the frame clock.
    @MainActor
    private final class Driver {
        let app: TestApp
        let builds = RowBuilds()
        private var nanos: Int64 = 0
        private let model: WalkCostModel

        init(rows: Int, button: Int?) {
            let model = WalkCostModel()
            self.model = model
            let builds = builds
            app = TestApp(width: 30, height: 12) {
                ModelPage(model: model, builds: builds, rows: rows, button: button)
            }
        }

        private struct ModelPage: View {
            let model: WalkCostModel
            let builds: RowBuilds
            let rows: Int
            let button: Int?
            var body: some View {
                Page(builds: builds, rows: rows, button: button, generation: model.generation)
            }
        }

        /// Draws one frame: the rows it built.
        func frame() -> Int {
            builds.count = 0
            _ = app.takeFrameRequest()
            nanos += 16_666_667
            app.frame(atNanos: nanos)
            return builds.count
        }

        /// Sends `event` and draws one frame: the rows it built.
        func send(_ event: KeyEvent) -> Int {
            _ = app.send(event)
            return frame()
        }

        /// Changes the rows' data and draws one frame: the rows it built.
        func changeRows() -> Int {
            model.generation += 1
            return frame()
        }

        var focusedID: String? { app.headless.focusedID }
    }

    /// The rows built by each frame: the first has no ring to go by; the
    /// second, with the focus on `top` and Tab from it landing on the scroll
    /// view's stop, asks every row once whether it has something to focus
    /// (10,014 rows: the walk and the screen's); after it, none until the rows'
    /// data changes, Tab onto the stop included, and the walk is made again
    /// once when they do (the focus, on the stop, still beside the stack).
    @Test("A button over 10,000 lines of text: every row walked once, then not until the rows change")
    func focuslessStackWalkedOncePerData() {
        let driver = Driver(rows: 10_000, button: nil)
        let frames = (0..<5).map { _ in driver.frame() }
        #expect(driver.focusedID == "top")
        #expect(frames[0] < 50 && frames[1] >= 10_000 && frames[1] < 10_050, "\(frames)")
        #expect(frames.dropFirst(2).allSatisfy { $0 < 50 }, "\(frames)")
        let tab = driver.send(KeyEvent(key: .tab))
        #expect(driver.focusedID?.hasPrefix("scrollview-") == true)
        let after = (0..<3).map { _ in driver.frame() }
        #expect(tab < 50 && after.allSatisfy { $0 < 50 }, "\(tab) \(after)")
        let changed = driver.changeRows()
        #expect(changed >= 10_000 && changed < 10_050, "\(changed)")
    }

    /// The walk to a button 300 rows down is made once (317 rows: the walk
    /// and the screen's), the key goes to the button, and the frames after
    /// ask the row found again alone.
    @Test("Tab from a button over 300 lines of text to a button: the walk once, then that row alone")
    func foundRowAskedAlone() {
        let driver = Driver(rows: 10_000, button: 300)
        let frames = (0..<5).map { _ in driver.frame() }
        #expect(frames[1] >= 300 && frames[1] < 350, "\(frames)")
        #expect(frames.dropFirst(2).allSatisfy { $0 < 50 }, "\(frames)")
        _ = driver.send(KeyEvent(key: .tab))
        #expect(driver.focusedID == "b300")
        let after = (0..<3).map { _ in driver.frame() }
        #expect(after.allSatisfy { $0 < 50 }, "\(after)")
    }
}
