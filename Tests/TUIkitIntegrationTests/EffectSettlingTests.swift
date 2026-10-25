//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectSettlingTests.swift
//
//  A frame is written once what its views did has settled (decisions
//  B-D5G-11): the effects run after the walk, in SwiftUI's order, and a walk
//  whose effects wrote state is walked again before the frame reaches the
//  terminal. Every test here reads the frame WRITTEN — `HeadlessApp.screen`,
//  what the diff writer put on the screen — not the state the effects left.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Whether any row of `screen` contains `text`.
private func shows(_ text: String, on screen: [String]) -> Bool {
    screen.contains { $0.stripped.contains(text) }
}

/// An app whose one window shows `Page`.
private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page
    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.page = { fatalError("built with init(_:)") } }
    init(_ page: @escaping @MainActor () -> Page) { self.page = page }
    var body: some Scene { WindowGroup { page() } }
}

/// A page that loads its rows in `onAppear`, with a count drawn above the
/// rows — before the view whose `onAppear` loads them — and one below.
private struct LoadingPage: View {
    @State private var items: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("above \(items.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { Text("row \($0)") }
            }
            .onAppear { items = ["a", "b", "c"] }
            Text("below \(items.count)")
        }
    }
}

/// A value an `onChange` derives another from, written from outside.
@MainActor
@Observable
private final class Source {
    var value = 0
}

/// A derived value drawn above the `onChange` that derives it, and below.
private struct DerivingPage: View {
    let source: Source
    @State private var derived = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("derived above \(derived)")
            Text("source \(source.value)")
                .onChange(of: source.value) { _, new in derived = new * 10 }
            Text("derived below \(derived)")
        }
    }
}

/// The widest of its rows, collected by a preference.
private struct WidestRow: PreferenceKey {
    static var defaultValue: Int { 0 }
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

/// The flow-layout idiom: rows report their sizes up through a preference,
/// an `onPreferenceChange` keeps them in `@State`, and the layout reads it.
private struct MeasuredLayoutPage: View {
    @State private var widest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("widest \(widest)")
            Text(String(repeating: "=", count: max(1, widest)))
            VStack(alignment: .leading, spacing: 0) {
                Text("abc").preference(key: WidestRow.self, value: 3)
                Text("abcdefg").preference(key: WidestRow.self, value: 7)
            }
            .onPreferenceChange(WidestRow.self) { widest = $0 }
        }
    }
}

/// A sibling drawn before a view whose `onGeometryChange` writes its width.
private struct GeometryFedPage: View {
    @State private var width = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("width \(width)")
            Text("twelve chars")
                .onGeometryChange(for: Int.self) { $0.size.width } action: { width = $0 }
        }
    }
}

/// A chain of four `onChange`s, each setting the next value from the last.
private struct ChainPage: View {
    @State private var steps = [0, 0, 0, 0, 0]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("chain \(steps.map(String.init).joined(separator: ","))")
                .onAppear { steps[0] = 1 }
                .onChange(of: steps[0]) { steps[1] = 1 }
                .onChange(of: steps[1]) { steps[2] = 1 }
                .onChange(of: steps[2]) { steps[3] = 1 }
                .onChange(of: steps[3]) { steps[4] = 1 }
        }
    }
}

/// A marker an `onAppear` slides across under `withAnimation`: the
/// appear-animation idiom.
private struct SlidesInPage: View {
    @State private var isAcross = false

    var body: some View {
        Text("@")
            .padding(.leading, isAcross ? 10 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { withAnimation(.linear(duration: 1)) { isAcross = true } }
    }
}

/// A page that writes nothing from its effects.
private struct QuietPage: View {
    var body: some View {
        Text("quiet")
            .onAppear {}
            .onChange(of: 1) {}
    }
}

@MainActor
@Suite("A frame is written once its effects have settled")
struct EffectSettlingTests {
    @Test("The first frame written of a page that loads in onAppear shows what it loaded, above and below the loader")
    func onAppearLoadsInTheFirstFrame() {
        let app = HeadlessApp(PageApp { LoadingPage() }, width: 30, height: 8)
        app.frame(atNanos: 0)
        #expect(shows("above 3", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(shows("row c", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(shows("below 3", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(app.effectSettling.walkedAgainOnce == 1, "\(app.effectSettling)")
    }

    @Test("A value an onChange derives is drawn in the frame that shows its source, on both sides of it")
    func onChangeDerivesInTheSameFrame() {
        let source = Source()
        let app = HeadlessApp(PageApp { DerivingPage(source: source) }, width: 30, height: 6)
        app.frame(atNanos: 0)
        #expect(shows("derived above 0", on: app.screen))
        source.value = 4
        app.frame(atNanos: 16_666_667)
        #expect(shows("source 4", on: app.screen))
        #expect(shows("derived above 40", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(shows("derived below 40", on: app.screen), "\(app.screen.map(\.stripped))")
    }

    @Test("Sizes a preference feeds back into the layout are in the first frame written: no flash of the empty layout")
    func preferenceFedLayoutDoesNotFlash() {
        let app = HeadlessApp(PageApp { MeasuredLayoutPage() }, width: 30, height: 6)
        app.frame(atNanos: 0)
        #expect(shows("widest 7", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(shows("=======", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(!shows("widest 0", on: app.screen))
    }

    @Test("A width onGeometryChange writes is drawn by a sibling before it in the first frame written")
    func geometryFedSiblingInTheFirstFrame() {
        let app = HeadlessApp(PageApp { GeometryFedPage() }, width: 30, height: 6)
        app.frame(atNanos: 0)
        #expect(shows("width 12", on: app.screen), "\(app.screen.map(\.stripped))")
    }

    @Test("A chain of effects is walked again twice before the frame is written, then carries on a walk a frame")
    func chainCarriesOn() {
        let app = HeadlessApp(PageApp { ChainPage() }, width: 30, height: 4)
        app.frame(atNanos: 0)
        // The onAppear's write, then the first change's: two walks more.
        #expect(shows("chain 1,1,0,0,0", on: app.screen), "\(app.screen.map(\.stripped))")
        #expect(app.effectSettling.walkedAgainTwice == 1 && app.effectSettling.leftWriting == 1, "\(app.effectSettling)")
        app.frame(atNanos: 16_666_667)
        #expect(shows("chain 1,1,1,1,1", on: app.screen), "\(app.screen.map(\.stripped))")
    }

    @Test("An onAppear's withAnimation animates from what the walk before it drew, which was never written")
    func appearAnimationStartsFromTheFirstWalk() {
        let app = HeadlessApp(PageApp { SlidesInPage() }, width: 30, height: 4)
        func column() -> Int? {
            for line in app.screen.map(\.stripped) {
                if let range = line.range(of: "@") { return line.distance(from: line.startIndex, to: range.lowerBound) }
            }
            return nil
        }
        app.frame(atNanos: 0)
        let first = column()
        #expect(first == 0, "the slide starts where the first walk drew the marker: \(app.screen.map(\.stripped))")
        app.frame(atNanos: 500_000_000)
        let middle = column() ?? 0
        #expect(middle > 0 && middle < 10, "part-way at half the animation: \(middle)")
        app.frame(atNanos: 1_100_000_000)
        #expect(column() == 10)
    }

    @Test("A frame whose effects write nothing is walked once")
    func quietEffectsWalkOnce() {
        let app = HeadlessApp(PageApp { QuietPage() }, width: 30, height: 4)
        for frame in 0..<3 { app.frame(atNanos: Int64(frame) * 16_666_667) }
        #expect(shows("quiet", on: app.screen))
        #expect(app.effectSettling.frames == 3)
        #expect(app.effectSettling.walkedAgainOnce == 0 && app.effectSettling.walkedAgainTwice == 0)
    }
}
