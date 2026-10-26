//  🖥️ TUI — A Terminal UI framework for Swift
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

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

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

/// A switch only a top-level `Toggle`'s binding reads — in the toggle's core,
/// where no body's scope sees it — turned on by an `onAppear` drawn after it.
@MainActor
@Observable
private final class Lamp {
    var isOn = false
    init(isOn: Bool) { self.isOn = isOn }
}

private struct LampPage: View {
    let lamp: Lamp
    let turnsOnAtAppear: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("lamp", isOn: Bindable(lamp).isOn)
            Text("switch").onAppear { if turnsOnAtAppear { lamp.isOn = true } }
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

/// An `onChange(of: x)` that sets `x + 1`, as far as 200: SwiftUI's
/// self-loop, which an outside write starts again.
private struct SelfLoopPage: View {
    let source: Source
    @State private var x = 0

    var body: some View {
        Text("x \(x)")
            .onAppear { x = 1 }
            .onChange(of: x) { if x < 200 { x += 1 } }
            .onChange(of: source.value) { x = 100 }
    }
}

/// The value a preference is made from, set by its own observer to what it
/// heard + 1, as far as 200.
private struct LoopKey: PreferenceKey {
    static var defaultValue: Int { 0 }
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

private struct PreferenceLoopPage: View {
    @State private var n = 0

    var body: some View {
        Text("n \(n)")
            .preference(key: LoopKey.self, value: n)
            .onPreferenceChange(LoopKey.self) { if $0 < 200 { n = $0 + 1 } }
    }
}

/// A view whose width its own `onGeometryChange` flips: three cells wide
/// makes it six, six makes it three.
private struct FlippingWidthPage: View {
    @State private var wide = false

    var body: some View {
        Text(String(repeating: "w", count: wide ? 6 : 3))
            .onGeometryChange(for: Int.self) { $0.size.width } action: { wide = $0 == 3 }
    }
}

/// The first number after `prefix` on `screen`.
private func number(after prefix: String, on screen: [String]) -> Int? {
    for line in screen.map(\.stripped) {
        guard let range = line.range(of: prefix) else { continue }
        return Int(line[range.upperBound...].prefix { $0.isNumber })
    }
    return nil
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

    @Test("An onAppear's write that only a top-level control's binding reads is in the first frame written")
    func bindingReadSettles() {
        // One lamp each, held outside the page: a walk made again evaluates
        // the app's body again, and a lamp made there would be a new one.
        let off = Lamp(isOn: false)
        let on = Lamp(isOn: true)
        let turnedOn = HeadlessApp(PageApp { LampPage(lamp: off, turnsOnAtAppear: true) }, width: 30, height: 4)
        turnedOn.frame(atNanos: 0)
        let alreadyOn = HeadlessApp(PageApp { LampPage(lamp: on, turnsOnAtAppear: false) }, width: 30, height: 4)
        alreadyOn.frame(atNanos: 0)
        #expect(turnedOn.screen == alreadyOn.screen, "\(turnedOn.screen.map(\.stripped))")
        #expect(turnedOn.effectSettling.walkedAgainOnce == 1, "\(turnedOn.effectSettling)")
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

    @Test("An onChange that keeps triggering itself runs twice a frame; the third is refused, with SwiftUI's warning")
    func selfTriggeringOnChangeIsCutOff() {
        let source = Source()
        let app = HeadlessApp(PageApp { SelfLoopPage(source: source) }, width: 30, height: 4)
        var drawn: [Int] = []
        for frame in 0..<6 {
            app.frame(atNanos: Int64(frame) * 16_666_667)
            drawn.append(number(after: "x ", on: app.screen) ?? -1)
        }
        #expect(drawn.last.map { $0 < 200 } == true, "the loop ran on: \(drawn)")
        #expect(Set(drawn.suffix(3)).count == 1, "the loop stopped: \(drawn)")
        #expect(SoftTrap.recorded.contains("onChange(of: Int) action tried to update multiple times per frame."))
        // The change refused is dropped, not deferred; a later write starts
        // the action again.
        let stopped = drawn.last ?? 0
        source.value = 1
        app.frame(atNanos: 6 * 16_666_667)
        let restarted = number(after: "x ", on: app.screen) ?? -1
        #expect(restarted > 100 && restarted != stopped, "\(restarted)")
    }

    @Test("An onPreferenceChange that feeds its own preference runs twice a frame; the third is refused, with SwiftUI's warning")
    func selfFeedingPreferenceIsCutOff() {
        let app = HeadlessApp(PageApp { PreferenceLoopPage() }, width: 30, height: 4)
        var drawn: [Int] = []
        for frame in 0..<6 {
            app.frame(atNanos: Int64(frame) * 16_666_667)
            drawn.append(number(after: "n ", on: app.screen) ?? -1)
        }
        #expect(drawn.last.map { $0 < 200 } == true, "the loop ran on: \(drawn)")
        #expect(Set(drawn.suffix(3)).count == 1, "the loop stopped: \(drawn)")
        #expect(SoftTrap.recorded.contains("Bound preference LoopKey tried to update multiple times per frame."))
    }

    @Test("An onGeometryChange whose action moves its view back to the size before last is refused, with SwiftUI's warning")
    func geometryCycleIsCutOff() {
        let app = HeadlessApp(PageApp { FlippingWidthPage() }, width: 30, height: 4)
        var drawn: [String] = []
        for frame in 0..<4 {
            app.frame(atNanos: Int64(frame) * 16_666_667)
            drawn.append(app.screen.map(\.stripped).first { $0.contains("w") } ?? "")
        }
        #expect(Set(drawn).count == 1, "it settled in the first frame: \(drawn)")
        #expect(SoftTrap.recorded.contains("Geometry action is cycling between duplicate values."))
        #expect(app.effectSettling.leftWriting == 0, "\(app.effectSettling)")
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
