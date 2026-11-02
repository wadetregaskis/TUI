//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainMemoCorrectnessTests.swift
//
//  What the memo on plain composites must not serve stale,
//  through the real render loop, with the memo switched on for the app under
//  test. See Documentation/Working notes/plain-body-memo-study.md.
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

/// A plain class nothing observes: what a body reads that no key sees.
@MainActor
private final class Unwatched {
    var value = 0
    static let shared = Unwatched()
}

private struct ProbeApp<Content: View>: App {
    let content: Content
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its content") }
    init(content: Content) { self.content = content }
    var body: some Scene { WindowGroup { content } }
}

private struct Label: View {
    let tag: String
    let value: Int
    var body: some View {
        Probe.note(tag)
        return Text(verbatim: "\(tag)=\(value)")
    }
}

private struct OwnState: View {
    @State private var count = 0
    var body: some View {
        Probe.note("own")
        Probe.write = { count += 1 }
        return Text(verbatim: "own=\(count)")
    }
}

/// A `ForEach` row whose element moves, with a composite in it that doesn't.
private struct MovingRow: View {
    struct Item: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    let item: Item
    var body: some View {
        VStack {
            Text(verbatim: item.text)
            Label(tag: "inside", value: 7)
        }
    }
}

private struct MovingRowPage: View {
    @State private var text = "a"
    var body: some View {
        Probe.write = { text += "b" }
        return VStack {
            ForEach([MovingRow.Item(id: 1, text: text)]) { MovingRow(item: $0) }
        }
    }
}

private struct PassesField: View {
    @State private var count = 0
    var body: some View {
        Probe.write = { count += 1 }
        return VStack {
            Label(tag: "changes", value: count)
            Label(tag: "same", value: 7)
        }
    }
}

private struct ClosureChild: View {
    let text: () -> String
    var body: some View {
        Probe.note("closure")
        return Text(verbatim: text())
    }
}

private struct PassesClosure: View {
    @State private var count = 0
    var body: some View {
        Probe.write = { count += 1 }
        return VStack {
            Text(verbatim: "top")
            ClosureChild(text: { "closure=\(count)" })
        }
    }
}

@Observable
private final class Model {
    var value = 0
}

private struct ReadsModel: View {
    let model: Model
    var body: some View {
        Probe.note("model")
        return Text(verbatim: "model=\(model.value)")
    }
}

private struct ReadsEnabled: View {
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Probe.note("enabled")
        return Text(verbatim: "enabled=\(isEnabled)")
    }
}

private struct DisablesChild: View {
    @State private var disabled = false
    var body: some View {
        Probe.write = { disabled.toggle() }
        return VStack {
            Text(verbatim: "top")
            ReadsEnabled().disabled(disabled)
        }
    }
}

private struct InkedChild: View {
    @State private var red = false
    var body: some View {
        Probe.write = { red.toggle() }
        return VStack {
            Text(verbatim: "top")
            Label(tag: "ink", value: 1).foregroundStyle(red ? Color.red : Color.green)
        }
    }
}

private struct ReadsUnwatched: View {
    var body: some View {
        Probe.note("unwatched")
        return Text(verbatim: "unwatched=\(Unwatched.shared.value)")
    }
}

private struct TwoButtons: View {
    @Binding var pressed: Int
    var body: some View {
        Probe.note("buttons")
        return VStack {
            Button("one") { pressed += 1 }
            Button("two") { pressed += 10 }
        }
    }
}

private struct ButtonsBesideLeaf: View {
    @State private var pressed = 0
    var body: some View {
        VStack {
            Text(verbatim: "pressed=\(pressed)")
            TwoButtons(pressed: $pressed)
        }
    }
}

/// Holds a button whose binding reads nothing, and a leaf whose write should
/// leave it alone: a closure field, no comparison, served by purity.
private struct ActionHolder: View {
    let action: () -> Void
    var body: some View {
        Probe.note("holder")
        return Button("act", action: action)
    }
}

private final class Tally: @unchecked Sendable {
    var count = 0
}

private struct AppearsOnce: View {
    let tally: Tally
    var body: some View {
        Probe.note("appears")
        return Text(verbatim: "appears").onAppear { tally.count += 1 }
    }
}

private struct KeepsState: View {
    @State private var count = 0
    var body: some View {
        Probe.write = { count += 1 }
        return Text(verbatim: "keeps=\(count)")
    }
}

private struct Toggler: View {
    @State private var showing = true
    var body: some View {
        Probe.write = { showing.toggle() }
        return VStack {
            Text(verbatim: "top")
            if showing { Label(tag: "shown", value: 1) }
        }
    }
}

private struct WidthLabel: View {
    let width: Int
    var body: some View {
        Probe.note("width")
        return Text(verbatim: "width=\(width)")
    }
}

/// A style that hands what the control knows to a composite of the app's own, by value.
private struct PressLabel: View {
    let isFocused: Bool
    var body: some View {
        Text(verbatim: isFocused ? "[FOCUSED]" : "[idle]")
    }
}

private struct LabelStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressLabel(isFocused: configuration.isFocused)
    }
}

private struct Leaf: View {
    @State private var count = 0
    var body: some View {
        Probe.write = { count += 1 }
        return Text(verbatim: "leaf=\(count)")
    }
}

@MainActor
@Suite("The memo on plain composites does not serve stale", .serialized)
struct PlainMemoCorrectnessTests {
    private func app<V: View>(_ content: V, width: Int = 40, height: Int = 10) -> HeadlessApp {
        Probe.reset()
        let app = HeadlessApp(ProbeApp(content: content), width: width, height: height)
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

    @Test("A sibling of a written leaf runs no body, and a closure field does not stop it")
    func siblingServed() {
        let app = app(
            VStack {
                Leaf()
                Label(tag: "a", value: 1)
                ClosureChild(text: { "closure" })
            })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        _ = Probe.take("a")
        _ = Probe.take("closure")
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("leaf=1"))
        #expect(Probe.take("a") == 0)
        #expect(Probe.take("closure") == 0)
    }

    @Test("A view's own state")
    func ownState() {
        let app = app(VStack { OwnState() })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("own=1"))
    }

    @Test("A parent's write: the field that changed is drawn, the one that did not is served")
    func fieldFromParent() {
        let app = app(PassesField())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        _ = Probe.take("same")
        _ = Probe.take("changes")
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("changes=1"))
        #expect(Probe.take("changes") > 0)
        #expect(Probe.take("same") == 0)
    }

    @Test("A parent's write reaches a closure that captured what it wrote")
    func closureFromParent() {
        let app = app(PassesClosure())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("closure=1"))
    }

    @Test("An @Observable a body read")
    func observable() {
        let model = Model()
        let app = app(VStack { ReadsModel(model: model) })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        model.value = 4
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("model=4"))
    }

    @Test("An environment value a modifier writes without noting it")
    func environment() {
        let app = app(DisablesChild())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        #expect(text(app).contains("enabled=true"))
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("enabled=false"))
    }

    @Test("Ink above a plain view")
    func ink() {
        let app = app(InkedChild())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        let before = app.screen.joined(separator: "\n")
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(app.screen.joined(separator: "\n") != before)
    }

    @Test("Buttons in a served composite: Tab moves, Return acts, in the same frame's handlers")
    func buttonsServed() {
        let app = app(ButtonsBesideLeaf())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        _ = app.send(KeyEvent(key: .tab))
        settle(app, nanos: &nanos, frames: 2)
        let first = app.focusedID
        _ = app.send(KeyEvent(key: .enter))
        settle(app, nanos: &nanos, frames: 2)
        let pressedOnce = text(app)
        _ = app.send(KeyEvent(key: .tab))
        settle(app, nanos: &nanos, frames: 2)
        #expect(app.focusedID != first)
        _ = app.send(KeyEvent(key: .enter))
        settle(app, nanos: &nanos, frames: 2)
        print("[stale] buttons: first=\(first ?? "nil") then=\(app.focusedID ?? "nil") after-one=\(pressedOnce.prefix(40))")
        #expect(pressedOnce.contains("pressed=1") || pressedOnce.contains("pressed=10"))
        #expect(text(app).contains("pressed=11"))
    }

    @Test("A style hands the focus to a composite by value")
    func styleValue() {
        let app = app(
            VStack {
                Button("x") {}.buttonStyle(LabelStyle())
                Button("y") {}.buttonStyle(LabelStyle())
            })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        let before = text(app)
        _ = app.send(KeyEvent(key: .tab))
        settle(app, nanos: &nanos, frames: 2)
        let after = text(app)
        print("[stale] style: before=\(before.prefix(30)) after=\(after.prefix(30))")
        #expect(after.contains("[FOCUSED]"))
    }

    @Test("onAppear in a composite runs once, and the composite is not stored over it")
    func onAppear() {
        let tally = Tally()
        let app = app(
            VStack {
                Leaf()
                AppearsOnce(tally: tally)
            })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        Probe.write?()
        settle(app, nanos: &nanos, frames: 3)
        #expect(tally.count == 1)
    }

    @Test("State below a served composite survives, and a view that left loses it")
    func stateLifetime() {
        let app = app(VStack { KeepsState() })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        Probe.write?()
        settle(app, nanos: &nanos, frames: 4)
        #expect(text(app).contains("keeps=1"))
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("keeps=2"))
    }

    @Test("A view an if takes out and puts back")
    func conditional() {
        let app = app(Toggler())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        #expect(text(app).contains("shown=1"))
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(!text(app).contains("shown=1"))
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("shown=1"))
    }

    @Test("A GeometryReader's size reaches a composite by value")
    func geometry() {
        let app = app(GeometryReader { proxy in WidthLabel(width: proxy.size.width) })
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        #expect(text(app).contains("width=40"))
        app.resize(width: 30, height: 10)
        settle(app, nanos: &nanos, frames: 2)
        #expect(text(app).contains("width=30"))
    }

    /// Not what anyone would want, and what SwiftUI does: a read no key sees is
    /// not seen. The contract the memo takes, as SwiftUI's does, which
    /// `TUI_VERIFY_RENDER_MEMO` finds and `TUI_RUN_BODY_ON_EVERY_FRAME=1` undoes.
    @Test("A read nothing tracks stays as it was drawn")
    func untrackedRead() {
        let app = app(
            VStack {
                Leaf()
                ReadsUnwatched()
            })
        var nanos: Int64 = 0
        Unwatched.shared.value = 0
        settle(app, nanos: &nanos)
        Unwatched.shared.value = 5
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("unwatched=0"))
    }

    /// The row's value says whether what's in it changed, and it has a buffer and a
    /// size. A cheap composite in there asks nothing of its own, which `session/notes`
    /// paid 6% a frame for. One that takes real time does: `tree-root`'s rows are
    /// dropped by their parent's write, and what they hold is served.
    @Test("A composite inside a row has a memo only if it takes real time", arguments: [false, true])
    func compositeInsideARow(takesRealTime: Bool) {
        let app = app(MovingRowPage())
        // Anything measured is over the line, or nothing is, whatever this machine's speed.
        app.renderCache.plainMemo.heavySubtree = takesRealTime ? .zero : .seconds(100)
        app.renderCache.bodyKeep.keepsEveryBody = false
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        // Only a row that misses has what's in it measured: three times to be seen,
        // and then stored.
        for _ in 0..<4 {
            Probe.write?()
            settle(app, nanos: &nanos, frames: 1)
        }
        _ = Probe.take("inside")
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("abbbbb"))
        if takesRealTime {
            #expect(Probe.take("inside") == 0)
        } else {
            #expect(Probe.take("inside") > 0)
        }
    }

    @Test("What changes every frame stops asking, and what settles is served again")
    func gate() {
        let app = app(PassesField())
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        for _ in 0..<12 {
            Probe.write?()
            settle(app, nanos: &nanos, frames: 1)
        }
        #expect(app.renderCache.plainMemo.counts.cooled > 0)
        #expect(text(app).contains("changes=12"))
        // The sibling beside it was served throughout, and is not cooled.
        _ = (Probe.take("same"), Probe.take("changes"))
        Probe.write?()
        settle(app, nanos: &nanos, frames: 1)
        #expect(text(app).contains("changes=13"))
        #expect(Probe.take("same") == 0)
        // Quiet for longer than the longest cooldown: drawn from the cache.
        settle(app, nanos: &nanos, frames: 70)
        _ = Probe.take("changes")
        settle(app, nanos: &nanos, frames: 2)
        #expect(Probe.take("changes") == 0)
    }

    @Test("A real app's services leave its environment comparable, as a test's do")
    func realAppEnvironmentIsStamped() {
        let context = TUIContext(clipboard: SystemClipboard.Backend(), urlOpener: SystemURLOpener())
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: context)
        let stamps = EnvironmentStamps()
        #expect(stamps.build(environment) != nil, "uncomparable: \(stamps.uncomparableKeys.keys.map(EnvironmentStamps.debugName(of:)))")
    }

    @Test("Every module of the framework is on the list that keeps its views out")
    func frameworkModules() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        // Hold no view, or are tools: nothing of theirs reaches the memo.
        let holdNoViews: Set<String> = [
            "TUIEnvironmentDocs", "TUIEnvironmentDocsTool", "TUIMacros", "TUIMacrosPlugin", "TUIWidthCorpus",
        ]
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasPrefix("TUI") }
        for module in modules where !holdNoViews.contains(module) {
            #expect(FrameworkModules.names.contains(Substring(module)), "\(module) is not in FrameworkModules.names")
        }
    }
}
