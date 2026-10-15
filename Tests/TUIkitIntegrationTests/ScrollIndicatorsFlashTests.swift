//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollIndicatorsFlashTests.swift
//
//  `scrollIndicatorsFlash(onAppear:)` and `scrollIndicatorsFlash(trigger:)`:
//  half a second of highlight on the indicators each scrollable draws, in
//  every view that draws them (decisions B28).
//
//  Each case renders the same view with and without the modifier, at the same
//  frame times, and compares the bytes: a flash changes the indicators'
//  colours and nothing else, and only while it lasts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("scrollIndicatorsFlash")
struct ScrollIndicatorsFlashTests {

    /// Frames of one view, at frame times the test chooses.
    @MainActor
    private final class Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let style: ScrollIndicatorStyle

        init(style: ScrollIndicatorStyle) { self.style = style }

        /// The frame's lines as drawn, escapes and all — a frame of the run
        /// loop, which can be followed by more (`canAnimate`), unless `oneOff`.
        func render<V: View>(_ view: V, atNanos nanos: Int64, oneOff: Bool = false) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.scrollIndicatorStyle = style
            environment.verticalScrollIndicatorVisibility = .visible
            environment.applyRuntimeServices(from: tuiContext)
            environment.animationFrame = AnimationFrame(nowNanos: nanos, canAnimate: !oneOff)
            let context = RenderContext(
                availableWidth: 24, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines
        }
    }

    /// The scrollables a flash reaches, each overflowing an eight-line frame.
    enum Kind: String, CaseIterable, CustomTestStringConvertible {
        case scrollView, list, table, textEditor

        var testDescription: String { rawValue }

        /// TextEditor draws a bar only: it has no "N more" lines.
        var styles: [ScrollIndicatorStyle] { self == .textEditor ? [.scrollbar] : [.scrollbar, .text] }

        @MainActor @ViewBuilder
        func view() -> some View {
            switch self {
            case .scrollView:
                ScrollView {
                    VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("row \($0)") } }
                }
            case .list:
                List(0..<30, id: \.self) { Text("row \($0)") }
            case .table:
                Table((0..<30).map { FlashRow(id: $0, name: "row \($0)") }) {
                    TableColumn("Name", value: \.name)
                }
            case .textEditor:
                TextEditor(text: .constant((0..<30).map { "line \($0)" }.joined(separator: "\n")))
            }
        }
    }

    private static let start: Int64 = 1_000_000_000
    private static let millisecond: Int64 = 1_000_000

    /// Renders `flashing` and `plain` side by side at `nanos`, and reports
    /// whether they differ, after checking that they draw the same text.
    private func differs<A: View, B: View>(
        _ flashing: A, _ plain: B, at nanos: Int64, _ frames: (Frames, Frames),
        _ comment: Comment
    ) -> Bool {
        let lit = frames.0.render(flashing, atNanos: nanos)
        let still = frames.1.render(plain, atNanos: nanos)
        #expect(lit.map(\.stripped) == still.map(\.stripped), "a flash changes colours only: \(comment)")
        return lit != still
    }

    @Test(
        "A scrollable flashes its indicators when it appears, for half a second",
        arguments: Kind.allCases)
    func flashesOnAppear(_ kind: Kind) {
        for style in kind.styles {
            let frames = (Frames(style: style), Frames(style: style))
            let flashing = kind.view().scrollIndicatorsFlash(onAppear: true)
            let plain = kind.view()
            #expect(differs(flashing, plain, at: Self.start, frames, "\(kind) \(style), appearing"))
            #expect(
                differs(flashing, plain, at: Self.start + 100 * Self.millisecond, frames, "\(kind) \(style), at its peak"))
            #expect(
                !differs(flashing, plain, at: Self.start + 600 * Self.millisecond, frames, "\(kind) \(style), done"))
        }
    }

    @Test(
        "A scrollable flashes its indicators when the trigger changes, and not for its first value",
        arguments: Kind.allCases)
    func flashesOnTrigger(_ kind: Kind) {
        for style in kind.styles {
            let frames = (Frames(style: style), Frames(style: style))
            let plain = kind.view()
            #expect(
                !differs(
                    kind.view().scrollIndicatorsFlash(trigger: 0), plain, at: Self.start, frames,
                    "\(kind) \(style), first value"))
            let changed = Self.start + 2_000 * Self.millisecond
            #expect(
                differs(
                    kind.view().scrollIndicatorsFlash(trigger: 1), plain, at: changed, frames,
                    "\(kind) \(style), changed"))
            #expect(
                differs(
                    kind.view().scrollIndicatorsFlash(trigger: 1), plain, at: changed + 250 * Self.millisecond,
                    frames, "\(kind) \(style), still flashing"))
            #expect(
                !differs(
                    kind.view().scrollIndicatorsFlash(trigger: 1), plain, at: changed + 500 * Self.millisecond,
                    frames, "\(kind) \(style), done"))
        }
    }

    /// A framework scroller — a tall menu's column, a dialog body's, a framed
    /// container's — takes none of the page's settings for its scroll views
    /// (`ScrollView.asChrome()`); a page's flash lit its bar each time one
    /// appeared, and on every change of a page's trigger (lane SCROLLB's
    /// review).
    @Test("A framework scroller's indicators do not flash for the page's request, either form")
    func chromeScrollerDoesNotFlash() {
        let chrome = ScrollView {
            VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("row \($0)") } }
        }
        .asChrome()
        for style in [ScrollIndicatorStyle.scrollbar, .text] {
            let appearing = (Frames(style: style), Frames(style: style))
            #expect(
                !differs(
                    chrome.scrollIndicatorsFlash(onAppear: true), chrome, at: Self.start, appearing,
                    "\(style), appearing"))
            let triggered = (Frames(style: style), Frames(style: style))
            _ = differs(chrome.scrollIndicatorsFlash(trigger: 0), chrome, at: Self.start, triggered, "first value")
            #expect(
                !differs(
                    chrome.scrollIndicatorsFlash(trigger: 1), chrome, at: Self.start + 2_000 * Self.millisecond,
                    triggered, "\(style), changed"))
        }
    }

    /// A render nothing follows — a snapshot — showed the flash's first step,
    /// half lit, and never the rest (lane SCROLLB's review): changes snap
    /// where `canAnimate` is false.
    @Test("A one-off render draws no flash", arguments: Kind.allCases)
    func oneOffRenderDrawsNoFlash(_ kind: Kind) {
        for style in kind.styles {
            let lit = Frames(style: style).render(
                kind.view().scrollIndicatorsFlash(onAppear: true), atNanos: Self.start, oneOff: true)
            let still = Frames(style: style).render(kind.view(), atNanos: Self.start, oneOff: true)
            #expect(lit == still, "\(kind) \(style)")
        }
    }

    @Test("A flash on appearing is false by default, and `false` flashes nothing")
    func onAppearFalseFlashesNothing() {
        let frames = (Frames(style: .scrollbar), Frames(style: .scrollbar))
        let view = Kind.scrollView.view()
        #expect(!differs(view.scrollIndicatorsFlash(onAppear: false), view, at: Self.start, frames, "false"))
    }

    @Test("A flash is half a second of 50 ms steps that rises, holds and fades")
    func timing() {
        #expect(ScrollIndicatorFlash.stepNanos == 50 * Self.millisecond)
        #expect(ScrollIndicatorFlash.stepNanos * Int64(ScrollIndicatorFlash.steps) == 500 * Self.millisecond)
        let ramp = (0..<ScrollIndicatorFlash.steps).map(ScrollIndicatorFlash.strength(atStep:))
        #expect(ramp == [0.5, 1, 1, 1, 1, 1, 0.8, 0.6, 0.4, 0.2])
    }

    @Test("A flash peaks past the far end of a focused bar's breath")
    func peakIsPastTheBreath() {
        let palette = EnvironmentValues().palette
        #expect(ScrollbarColors.flashPeak(palette) != ScrollbarColors.pulseLift(palette))
    }
}

/// A table row for the flash cases.
private struct FlashRow: Identifiable {
    let id: Int
    let name: String
}
