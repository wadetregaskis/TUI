//  🖥️ TUI — A Terminal UI framework for Swift
//  BodyKeepTests.swift
//
//  A measure's evaluation of a composite's `body` kept for the draw of the same
//  value in the same walk: how often a body runs, and what must still be fresh.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
private enum Runs {
    static var counts: [String: Int] = [:]
    static var write: (() -> Void)?
    static var nanos: Int64 = 0
    static func note(_ tag: String) { counts[tag, default: 0] += 1 }
    static func take(_ tag: String) -> Int {
        defer { counts[tag] = 0 }
        return counts[tag] ?? 0
    }
}

private struct KeepApp<Content: View>: App {
    let content: Content
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its content") }
    init(content: Content) { self.content = content }
    var body: some Scene { WindowGroup { content } }
}

private struct Writer: View {
    @State private var count = 0
    var body: some View {
        Runs.write = { count += 1 }
        return Text(verbatim: "count \(count)")
    }
}

private struct Plain: View {
    let tag: String
    var body: some View {
        Runs.note(tag)
        return Text(verbatim: tag)
    }
}

private struct HoldsArray: View {
    let tag: String
    let values: [Int]
    let inner: Bool
    var body: some View {
        Runs.note(tag)
        return Group {
            if inner { Self(tag: tag + "+", values: [values.count], inner: false) } else { Text(verbatim: tag) }
        }
    }
}

private struct ReadsState: View {
    @State private var value = 0
    var body: some View {
        Runs.note("state")
        Runs.write = { value += 1 }
        return Text(verbatim: "state \(value)")
    }
}

private struct ReadsEnvironment: View {
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Runs.note("env")
        return Text(verbatim: "enabled \(isEnabled)")
    }
}

private struct ReadsFocus: View {
    @FocusState private var focused: Bool
    var body: some View {
        Runs.note("focus")
        return Button(focused ? "focused" : "plain") {}.focused($focused)
    }
}

private struct Slow: View {
    var body: some View {
        Runs.note("slow")
        Thread.sleep(forTimeInterval: 0.002)
        return Text(verbatim: "slow")
    }
}

@Observable
@MainActor
private final class Model {
    var value = 0
}

private struct ReadsModel: View {
    let model: Model
    var body: some View {
        Runs.note("model")
        return Text(verbatim: "model \(model.value)")
    }
}

@MainActor
@Suite("A body measured is not run again to be drawn", .serialized)
struct BodyKeepTests {
    private func app<V: View>(_ content: V, keeping: Bool = true) -> HeadlessApp {
        Runs.counts = [:]
        Runs.write = nil
        let app = HeadlessApp(KeepApp(content: content), width: 50, height: 12)
        app.renderCache.bodyKeep.isOn = keeping
        app.renderCache.bodyKeep.keepsEveryBody = keeping
        app.renderCache.plainMemo.isOn = false
        return app
    }

    private func frames(_ app: HeadlessApp, _ count: Int = 1) {
        for _ in 0..<count {
            Runs.nanos += 16_700_000
            app.frame(atNanos: Runs.nanos)
        }
    }

    private func text(_ app: HeadlessApp) -> String { app.screen.map(\.stripped).joined(separator: "\n") }

    @Test("A sibling of a written leaf runs once a frame, where it ran twice")
    func onceAFrame() {
        let app = app(
            VStack {
                Writer()
                Plain(tag: "a")
                HStack { Plain(tag: "b") }
            })
        frames(app, 2)
        _ = (Runs.take("a"), Runs.take("b"))
        Runs.write?()
        frames(app)
        #expect(Runs.take("a") == 1)
        #expect(Runs.take("b") == 1)
        #expect(app.renderCache.bodyKeep.counts.taken > 0)
    }

    @Test("With it off, twice: what the count above is against")
    func twiceWithoutIt() {
        let app = app(
            VStack {
                Writer()
                Plain(tag: "a")
            }, keeping: false)
        frames(app, 2)
        _ = Runs.take("a")
        Runs.write?()
        frames(app)
        #expect(Runs.take("a") == 2)
        #expect(app.renderCache.bodyKeep.counts.kept == 0)
    }

    @Test("A nest holding what its parent built anew stays at one each")
    func nest() {
        let app = app(
            VStack {
                Writer()
                HoldsArray(tag: "outer", values: [1, 2], inner: true)
            })
        frames(app, 2)
        _ = (Runs.take("outer"), Runs.take("outer+"))
        Runs.write?()
        frames(app)
        #expect(Runs.take("outer") == 1)
        #expect(Runs.take("outer+") == 1)
    }

    @Test("State, written, draws what was written, on the frame it was written")
    func state() {
        let app = app(VStack { ReadsState() })
        frames(app, 2)
        Runs.write?()
        frames(app)
        #expect(text(app).contains("state 1"))
        Runs.write?()
        frames(app)
        #expect(text(app).contains("state 2"))
    }

    @Test("An environment a modifier changes between frames is drawn")
    func environment() {
        struct Page: View {
            @State private var disabled = false
            var body: some View {
                Runs.write = { disabled.toggle() }
                return VStack { ReadsEnvironment() }.disabled(disabled)
            }
        }
        let app = app(Page())
        frames(app, 2)
        #expect(text(app).contains("enabled true"))
        Runs.write?()
        frames(app)
        #expect(text(app).contains("enabled false"))
    }

    @Test("A model read while measured is observed, as it is drawn from what the measure read")
    func observed() {
        let model = Model()
        let app = app(VStack { ReadsModel(model: model) })
        frames(app, 2)
        #expect(text(app).contains("model 0"))
        _ = Runs.take("model")
        model.value = 5
        #expect(app.takeFrameRequest())
        frames(app)
        #expect(text(app).contains("model 5"))
        #expect(Runs.take("model") == 1)
    }

    @Test("A view reading the focus is evaluated for its draw: the draw settles the focus")
    func focus() {
        let app = app(VStack { ReadsFocus() })
        frames(app, 2)
        _ = Runs.take("focus")
        frames(app)
        #expect(Runs.take("focus") >= 2)
        #expect(app.renderCache.bodyKeep.counts.taken == 0)
    }

    @Test("A body seen to take real time is kept, from the next frame, and a quick one is not")
    func onlyTheSlow() {
        let app = app(
            VStack {
                Writer()
                Slow()
                Plain(tag: "quick")
            })
        app.renderCache.bodyKeep.keepsEveryBody = false
        frames(app, 3)
        _ = (Runs.take("slow"), Runs.take("quick"))
        Runs.write?()
        frames(app)
        #expect(Runs.take("slow") == 1)
        #expect(Runs.take("quick") == 2)
    }

    @Test("Nothing is kept past the walk: the table holds environments, which hold the cache")
    func keepsNothingPastTheWalk() {
        let app = app(VStack { Plain(tag: "a") })
        frames(app, 2)
        #expect(app.renderCache.bodyKeep.isEmpty)
    }
}
