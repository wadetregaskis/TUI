//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainDataComparisonTests.swift
//
//  How the memos decide a view of plain data is unchanged, through the real
//  render loop: by its bytes where every one is defined, as SwiftUI does
//  (measured: Documentation/SwiftUI parity/POD-COMPARE), and by `==` only where
//  that rule says so (O-26, owner 2026-11-21).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
private enum Probe {
    static var runs: [String: Int] = [:]
    static var write: (() -> Void)?
    static func note(_ tag: String) { runs[tag, default: 0] += 1 }
    static func take(_ tag: String) -> Int {
        defer { runs[tag] = 0 }
        return runs[tag] ?? 0
    }
    static func reset() {
        runs = [:]
        write = nil
    }
}

private struct ProbeApp<Content: View>: App {
    let content: Content
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its content") }
    init(content: Content) { self.content = content }
    var body: some Scene { WindowGroup { content } }
}

/// Plain data whose `==` reads `id` alone, though a body draws `name` too.
private struct Item: Equatable {
    var id: Int
    var name: Int
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// The same, holding a `String`: not plain data.
private struct NamedItem: Equatable {
    var id: Int
    var name: Int
    var note: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

private struct Readout: View {
    let value: Double
    var body: some View {
        Probe.note("readout")
        return Text(verbatim: "value=\(value)")
    }
}

private struct ItemReadout: View {
    let item: Item
    var body: some View {
        Probe.note("item")
        return Text(verbatim: "name=\(item.name)")
    }
}

private struct NamedItemReadout: View {
    let item: NamedItem
    var body: some View {
        Probe.note("named")
        return Text(verbatim: "name=\(item.name)")
    }
}

/// A view of plain data that is `Equatable`, by `id` alone.
private struct EquatableItemReadout: View, Equatable {
    let item: Item
    var body: some View {
        Probe.note("equatable")
        return Text(verbatim: "name=\(item.name)")
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.item == rhs.item }
}

/// A view of plain data that is `Equatable` by its synthesized `==`.
private struct EquatableReadout: View, Equatable {
    let value: Double
    var body: some View {
        Probe.note("equatable")
        return Text(verbatim: "value=\(value)")
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
}

private struct Negates: View {
    @State private var value = 0.0
    var body: some View {
        Probe.write = { value = -value }
        return VStack {
            Text(verbatim: "top")
            Readout(value: value)
        }
    }
}

/// Writes a state nothing below reads, so its children are compared alone.
private struct Ticks<Content: View>: View {
    @State private var tick = 0
    let content: Content
    var body: some View {
        Probe.write = { tick += 1 }
        return VStack {
            Text(verbatim: "tick=\(tick)")
            content
        }
    }
}

/// Renames an item, keeping its `id`.
private struct Renames<Content: View>: View {
    @State private var name = 1
    let content: (Int) -> Content
    var body: some View {
        Probe.write = { name += 1 }
        return VStack {
            Text(verbatim: "top")
            content(name)
        }
    }
}

@MainActor
@Suite("A view of plain data is compared by its bytes where they are all defined", .serialized)
struct PlainDataComparisonTests {
    private func app<V: View>(_ content: V) -> HeadlessApp {
        Probe.reset()
        let app = HeadlessApp(ProbeApp(content: content), width: 40, height: 10)
        app.renderCache.plainMemo.isOn = true
        return app
    }

    private func settle(_ app: HeadlessApp, nanos: inout Int64, frames: Int = 3) {
        for _ in 0..<frames {
            app.frame(atNanos: nanos)
            nanos += 16_700_000
        }
    }

    private func text(_ app: HeadlessApp) -> String { app.screen.map(\.stripped).joined(separator: "\n") }

    /// Settles `app`, writes once, and draws one frame.
    private func writeOnce(_ app: HeadlessApp) {
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        Probe.runs = [:]
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
    }

    @Test("−0.0 after 0.0 is drawn: `==` calls them equal, their bytes differ")
    func negativeZero() {
        let app = app(Negates())
        writeOnce(app)
        #expect(text(app).contains("value=-0.0"))
    }

    @Test("A NaN field is served: `==` calls it unequal to itself, its bytes are the same")
    func notANumber() {
        let app = app(Ticks(content: Readout(value: .nan)))
        writeOnce(app)
        #expect(text(app).contains("tick=1"))
        #expect(Probe.take("readout") == 0)
    }

    @Test("Plain data whose `==` ignores a field the body draws: a change to that field is drawn")
    func equalityIgnoresAField() {
        let app = app(Renames { ItemReadout(item: Item(id: 1, name: $0)) })
        writeOnce(app)
        #expect(text(app).contains("name=2"))
    }

    @Test("A view of plain data that is `Equatable`, without `.equatable()`: its bytes, not its `==`")
    func equatableViewWithoutModifier() {
        let app = app(Renames { EquatableItemReadout(item: Item(id: 1, name: $0)) })
        writeOnce(app)
        #expect(text(app).contains("name=2"))
    }

    @Test("Data holding a `String` is not plain: its own `==` still decides")
    func notPlainData() {
        let app = app(Renames { NamedItemReadout(item: NamedItem(id: 1, name: $0, note: "note")) })
        writeOnce(app)
        #expect(text(app).contains("name=1"))
        #expect(Probe.take("named") == 0)
    }

    @Test("`.equatable()`: what `==` calls equal is served, though its bytes differ")
    func explicitKeepsEquality() {
        let app = app(Renames { EquatableItemReadout(item: Item(id: 1, name: $0)).equatable() })
        writeOnce(app)
        #expect(text(app).contains("name=1"))
        #expect(Probe.take("equatable") == 0)
    }

    @Test("`.equatable()`: what has the same bytes is served, though `==` calls it unequal")
    func explicitServesSameBytes() {
        let app = app(Ticks(content: EquatableReadout(value: .nan).equatable()))
        writeOnce(app)
        #expect(text(app).contains("tick=1"))
        #expect(Probe.take("equatable") == 0)
    }
}
