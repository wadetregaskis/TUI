//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerClosedMenuWorkTests.swift
//
//  What a closed menu `Picker` of many options costs a frame: how many of its
//  options' labels it draws, and how many it resolves, over a frame that
//  changes a sibling and over an idle one (H-92, CTRLS-2). It resolves and
//  measures them once a pass and draws only the option it shows, and still
//  sizes itself to its widest option.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPickers
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Page {
    var tick = 0
    var choice = 7
    @ObservationIgnored var labelBodies = 0
    @ObservationIgnored var resolutions = 0

    /// The option at `index`, counted each time the picker's `ForEach` makes it.
    func option(_ index: Int) -> some View {
        resolutions += 1
        return CountedLabel(index: index, page: self).tag(index)
    }
}

/// An option's label that counts its body's evaluations.
private struct CountedLabel: View {
    let index: Int
    let page: Page

    var body: some View {
        page.labelBodies += 1
        return Text(verbatim: "Option \(index)")
    }
}

private struct PickerPage: View {
    let page: Page
    let count: Int

    var body: some View {
        let page = page
        VStack(alignment: .leading) {
            Text(verbatim: "tick \(page.tick)")
            Picker("Choice", selection: Bindable(page).choice) {
                ForEach(0..<count, id: \.self) { index in page.option(index) }
            }
            Button("Other") {}
        }
    }
}

@MainActor
@Suite("What a closed menu picker draws a frame")
struct PickerClosedMenuWorkTests {
    private struct Counts: CustomStringConvertible {
        var labels: Int
        var resolutions: Int
        var description: String { "labels \(labels), resolutions \(resolutions)" }
    }

    private func counts(_ page: Page, _ step: () -> Void) -> Counts {
        page.labelBodies = 0
        page.resolutions = 0
        step()
        return Counts(labels: page.labelBodies, resolutions: page.resolutions)
    }

    @Test("A frame that changes a sibling draws each label at most twice, an idle one once")
    func labelsPerFrame() {
        let page = Page()
        let app = TestApp(width: 80, height: 24) { PickerPage(page: page, count: 500) }
        _ = app.screen
        app.advance(by: .milliseconds(17))
        // Before H-92: 2,000 labels and 4,000 resolutions over the sibling
        // frame, 500 and 1,500 over the idle one.
        let sibling = counts(page) {
            page.tick += 1
            app.advance(by: .milliseconds(17))
        }
        let idle = counts(page) { app.advance(by: .milliseconds(17)) }
        #expect(sibling.labels <= 1_001, "\(sibling)")
        #expect(sibling.resolutions <= 2_001, "\(sibling)")
        #expect(idle.labels <= 500, "\(idle)")
        #expect(idle.resolutions <= 1_000, "\(idle)")
        #expect(app.screen.contains("tick 1"))
        #expect(app.screen.contains("Option 7"))
    }

    @Test("The closed control keeps the widest option's width as a label grows and shrinks")
    func widthFollowsLabels() {
        let page = Page()
        let app = TestApp(width: 80, height: 24) { GrowingPage(page: page) }
        let narrow = app.screen.lines.first { $0.contains("Short") } ?? ""
        page.tick = 1
        app.advance(by: .milliseconds(17))
        let wide = app.screen.lines.first { $0.contains("Short") } ?? ""
        page.tick = 0
        app.advance(by: .milliseconds(17))
        let narrowAgain = app.screen.lines.first { $0.contains("Short") } ?? ""
        #expect(wide.trimmingTrailingSpaces.count == narrow.trimmingTrailingSpaces.count + 20)
        #expect(narrowAgain == narrow)
    }
}

/// A picker showing its short option, whose other, longer, option grows by 20
/// cells while `tick` is 1.
private struct GrowingPage: View {
    let page: Page

    var body: some View {
        let page = page
        Picker("", selection: Bindable(page).choice) {
            Text(verbatim: "Short").tag(7)
            Text(verbatim: "Longest" + String(repeating: "g", count: page.tick * 20)).tag(8)
        }
    }
}

private extension String {
    var trimmingTrailingSpaces: Substring {
        var end = endIndex
        while end > startIndex, self[index(before: end)] == " " { end = index(before: end) }
        return self[..<end]
    }
}
