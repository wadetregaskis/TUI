//  🖥️ TUI — A Terminal UI framework for Swift
//  RewalkNotedValueTests.swift
//
//  A frame walked again for what its effects wrote compares the values noted
//  in it again.
//
//  A `GeometryReader` notes the size it hands its content, as an environment
//  modifier notes the value it applies, and drops what is kept below it when
//  that moves. The note answered once a PASS: every visit after the first in
//  one pass was taken as unchanged without a look. A frame whose `onAppear`
//  or `onChange` writes state is walked again in the same pass, and in that
//  walk a reader beside the writer is offered another size; the note said
//  unchanged, the rows below were served as the first walk drew them, and
//  that is the frame written, with nothing asking for another.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// Flips the sidebar's width from outside, between frames.
@MainActor
private final class WidthTrigger {
    var binding: Binding<Int>?
    func bump() { binding?.wrappedValue += 1 }
}

/// A sidebar 4 cells wide that widens itself from its effects: to 30 as it
/// appears, as a saved width is loaded, and by 2 on each change of a trigger.
private struct EffectSidebar: View {
    @State private var width = 4
    @State private var trigger = 0
    let widensOnAppear: Bool
    let handle: WidthTrigger

    var body: some View {
        handle.binding = $trigger
        return Text(String(repeating: "s", count: width))
            .onAppear { if widensOnAppear { width = 30 } }
            .onChange(of: trigger) { width += 2 }
    }
}

/// The sidebar beside a reader whose rows print the reader's width. The rows
/// sit in a stack 20 cells wide, so each is memoized by its element and
/// offered the same 20 cells whatever size the reader has.
private struct EffectReaderPage: App {
    let widensOnAppear: Bool
    let handle: WidthTrigger

    init() { self.init(widensOnAppear: false, handle: WidthTrigger()) }

    init(widensOnAppear: Bool, handle: WidthTrigger) {
        self.widensOnAppear = widensOnAppear
        self.handle = handle
    }

    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 0) {
                EffectSidebar(widensOnAppear: widensOnAppear, handle: handle)
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            Text(verbatim: "row \(index) in \(proxy.size.width)")
                        }
                    }
                    .frame(width: 20, alignment: .leading)
                }
            }
        }
    }
}

@MainActor
@Suite("A frame walked again compares what it notes again")
struct RewalkNotedValueTests {
    private static func step(_ app: TestApp, _ frame: Int) {
        app.frame(atNanos: 1_000_000_000 + Int64(frame) * 16_666_667)
    }

    private func rows(_ app: TestApp) -> [String] {
        app.screen.styledLines.filter { $0.contains("row ") }
    }

    @Test("A width loaded in onAppear is the one the reader's rows print on the first frame")
    func onAppearWidthIsDrawnInTheFirstFrame() {
        let app = TestApp(EffectReaderPage(widensOnAppear: true, handle: WidthTrigger()), width: 60, height: 8)
        Self.step(app, 0)
        #expect(app.screen.styledLines.contains { $0.contains(String(repeating: "s", count: 30)) }, "precondition")
        #expect(rows(app).count == 3)
        #expect(rows(app).allSatisfy { $0.contains("in 30") }, "the first walk's width was written: \(rows(app))")
    }

    @Test("A width an onChange writes is the one the reader's rows print in that frame")
    func onChangeWidthIsDrawnInItsFrame() {
        let handle = WidthTrigger()
        let app = TestApp(EffectReaderPage(widensOnAppear: false, handle: handle), width: 60, height: 8)
        for frame in 0..<3 { Self.step(app, frame) }
        #expect(rows(app).allSatisfy { $0.contains("in 56") }, "precondition: \(rows(app))")

        handle.bump()
        Self.step(app, 3)
        #expect(rows(app).allSatisfy { $0.contains("in 54") }, "the first walk's width was written: \(rows(app))")
    }

    @Test("A change the rewalk drew is not cleared again on the next frame")
    func aDrawnChangeIsNotClearedAgain() {
        let handle = WidthTrigger()
        let app = TestApp(EffectReaderPage(widensOnAppear: false, handle: handle), width: 60, height: 8)
        for frame in 0..<3 { Self.step(app, frame) }
        handle.bump()
        Self.step(app, 3)
        let settled = app.renderCache.stats.subtreeClears
        Self.step(app, 4)
        #expect(app.renderCache.stats.subtreeClears == settled, "a size already drawn was found to have moved")
    }
}
