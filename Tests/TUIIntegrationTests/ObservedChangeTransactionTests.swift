//  🖥️ TUI — A Terminal UI framework for Swift
//  ObservedChangeTransactionTests.swift
//
//  One turn's changes are drawn in order, an update for each transaction, as
//  SwiftUI draws them: what `Tools/SwiftUIProbes/Transactions of observed
//  changes/` measured (`txn.out`, `txn2.out`), for `@Observable` properties and
//  for `@State`, in the updates a body is given and in the picture.
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

/// What the probes' bodies read.
@Observable
@MainActor
private final class Readings {
    var a = 0
    var b = 0
    var c = 0
}

/// What a body was given, in order: each update's values, and its animation,
/// as the probes' `.transaction(_:)` records them. A walk that changes nothing
/// a body read is not an update of anything, so a repeat is not noted.
///
/// A last transaction that animated is followed, as in `txn.out`, by the same
/// values, plain: SwiftUI's next update, and here the frame that shows it.
@MainActor
private final class UpdateLog {
    private(set) var updates: [String] = []
    private(set) var events: [String] = []

    func noteUpdate(_ update: String) {
        if updates.last != update { updates.append(update) }
    }

    func noteEvent(_ event: String) {
        events.append(event)
    }

    func clear() {
        updates = []
        events = []
    }
}

/// A transaction's animation, by the names the probes give them.
private func spelled(_ transaction: Transaction) -> String {
    switch transaction.animation {
    case nil: "plain"
    case .some(fast): "fast"
    case .some(slow): "slow"
    case .some: "other"
    }
}

private let fast = Animation.linear(duration: 1)
private let slow = Animation.linear(duration: 2)

// MARK: - Bodies

/// A body reading all three values, whose button plays a turn.
private struct ReadingsPage: View {
    let readings: Readings
    let log: UpdateLog
    let turn: @MainActor (Readings, UpdateLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") { turn(readings, log) }
            Text("\(readings.a) \(readings.b) \(readings.c)")
                .transaction { [readings, log] transaction in
                    let values = "a=\(readings.a) b=\(readings.b) c=\(readings.c)"
                    MainActor.assumeIsolated { log.noteUpdate("\(values) \(spelled(transaction))") }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A body reading two `@State`s, whose button plays a turn through their
/// bindings.
private struct StatePage: View {
    @State private var a = 0
    @State private var b = 0
    let log: UpdateLog
    let turn: @MainActor (Binding<Int>, Binding<Int>, UpdateLog) -> Void

    var body: some View {
        let (a, b) = (a, b)
        return VStack(alignment: .leading, spacing: 0) {
            Button("go") { turn($a, $b, log) }
            Text("\(a) \(b)")
                .transaction { [log] transaction in
                    MainActor.assumeIsolated { log.noteUpdate("a=\(a) b=\(b) \(spelled(transaction))") }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Two marks one body places, each by a value of its own.
private struct TwoMarksPage: View {
    let readings: Readings
    let turn: @MainActor (Readings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") { turn(readings) }
            Text("AAA").offset(x: readings.a)
            Text("BBB").offset(x: readings.b)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Two marks one body places by `@State`, as above.
private struct TwoStateMarksPage: View {
    @State private var a = 0
    @State private var b = 0
    let animatedFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") {
                if animatedFirst {
                    withAnimation(fast) { b = 20 }
                    a = 20
                } else {
                    a = 20
                    withAnimation(fast) { b = 20 }
                }
            }
            Text("AAA").offset(x: a)
            Text("BBB").offset(x: b)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// `onChange` of two values, as the probes record them.
private struct ChangesPage: View {
    let readings: Readings
    let log: UpdateLog
    let turn: @MainActor (Readings, UpdateLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") { turn(readings, log) }
            Text("\(readings.a) \(readings.b)").offset(x: readings.b)
        }
        .onChange(of: readings.a) { log.noteEvent("onChange a -> \(readings.a) (b=\(readings.b))") }
        .onChange(of: readings.b) { log.noteEvent("onChange b -> \(readings.b) (a=\(readings.a))") }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A panel closed plainly while a toast arrives animated: what a clip caught.
private struct PanelAndToastPage: View {
    @State private var panel = true
    @State private var toast = false
    let toastFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") {
                if toastFirst {
                    withAnimation(fast) { toast = true }
                    panel = false
                } else {
                    panel = false
                    withAnimation(fast) { toast = true }
                }
            }
            if panel { Text("PANEL").transition(.opacity) }
            if toast { Text("TOAST").transition(.move(edge: .leading)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - A harness for any of them

private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page

    // swiftlint:disable:next unavailable_function
    init() { fatalError("made with a page") }
    init(page: @escaping @MainActor () -> Page) { self.page = page }

    var body: some Scene {
        WindowGroup { page() }
    }
}

/// `page` in an app settled on the screen, and the frames its tests step.
@MainActor
private final class Harness<Page: View> {
    let app: HeadlessApp
    private var tick: Int64 = 0

    init(width: Int = 60, height: Int = 8, _ page: @escaping @MainActor () -> Page) {
        app = HeadlessApp(PageApp(page: page), width: width, height: height)
        step(2)
    }

    func step(_ frames: Int = 1) {
        for _ in 0..<frames {
            app.frame(atNanos: AnimationClock.nanoseconds(atTick: tick))
            tick += 1
        }
    }

    /// The column `text` is drawn at.
    func column(of text: String) -> Int? {
        for line in app.screen.map(\.stripped) {
            if let range = line.range(of: text) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }
}

@MainActor
@Suite("One turn's changes are drawn an update for each transaction, in order")
struct ObservedChangeTransactionTests {
    /// The updates a turn gives the body reading every value.
    private func updates(of turn: @escaping @MainActor (Readings, UpdateLog) -> Void) -> [String] {
        let (readings, log) = (Readings(), UpdateLog())
        let harness = Harness { ReadingsPage(readings: readings, log: log, turn: turn) }
        log.clear()
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        harness.step()
        return log.updates
    }

    /// The updates a turn gives the body reading two `@State`s.
    private func stateUpdates(of turn: @escaping @MainActor (Binding<Int>, Binding<Int>, UpdateLog) -> Void) -> [String] {
        let log = UpdateLog()
        let harness = Harness { StatePage(log: log, turn: turn) }
        log.clear()
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        harness.step()
        return log.updates
    }

    // MARK: Updates: `@Observable`

    @Test("A plain write, then an animated one: an update each, at the values between them")
    func plainThenAnimated() {
        let seen = updates { model, _ in
            model.a += 1
            withAnimation(fast) { model.b += 1 }
        }
        #expect(seen == ["a=1 b=0 c=0 plain", "a=1 b=1 c=0 fast", "a=1 b=1 c=0 plain"])
    }

    @Test("An animated write, then a plain one: an update each, at the values between them")
    func animatedThenPlain() {
        let seen = updates { model, _ in
            withAnimation(fast) { model.b += 1 }
            model.a += 1
        }
        #expect(seen == ["a=0 b=1 c=0 fast", "a=1 b=1 c=0 plain"])
    }

    @Test("One animated write, and one plain, are one update")
    func oneWrite() {
        #expect(updates { model, _ in withAnimation(fast) { model.b += 1 } } == ["a=0 b=1 c=0 fast", "a=0 b=1 c=0 plain"])
        #expect(updates { model, _ in model.a += 1 } == ["a=1 b=0 c=0 plain"])
    }

    @Test("A plain write, then a withAnimation that writes nothing, is drawn plain")
    func plainThenEmptyScope() {
        #expect(updates { model, _ in model.a += 1; withAnimation(fast) {} } == ["a=1 b=0 c=0 plain"])
        #expect(updates { model, _ in model.a += 1; withAnimation(fast) { _ = 0 } } == ["a=1 b=0 c=0 plain"])
    }

    @Test("Three writes in one scope are one update")
    func threeWritesInOneScope() {
        let seen = updates { model, _ in
            withAnimation(fast) {
                model.a += 1
                model.b += 1
                model.c += 1
            }
        }
        #expect(seen == ["a=1 b=1 c=1 fast", "a=1 b=1 c=1 plain"])
    }

    @Test("Two scopes of different animations are an update each")
    func twoScopes() {
        let seen = updates { model, _ in
            withAnimation(fast) { model.a += 1 }
            withAnimation(slow) { model.b += 1 }
        }
        #expect(seen == ["a=1 b=0 c=0 fast", "a=1 b=1 c=0 slow", "a=1 b=1 c=0 plain"])
    }

    @Test("A scope in a scope: outer, inner, outer again, in order")
    func nestedScopes() {
        let seen = updates { model, _ in
            withAnimation(fast) {
                model.a += 1
                withAnimation(slow) { model.b += 1 }
                model.c += 1
            }
        }
        #expect(seen == ["a=1 b=0 c=0 fast", "a=1 b=1 c=0 slow", "a=1 b=1 c=1 fast", "a=1 b=1 c=1 plain"])
    }

    /// SwiftUI gives this one update, since nothing the scope did needed
    /// another: TUI's walk comes as the scope begins, before it can know. The
    /// body runs once more, and nothing is drawn differently.
    @Test("A scope that only reads leaves every update plain")
    func scopeThatOnlyReads() {
        let seen = updates { model, _ in
            model.a += 1
            withAnimation(fast) { _ = model.c }
            model.b += 1
        }
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0.hasSuffix("plain") }, "\(seen)")
        #expect(seen.last == "a=1 b=1 c=0 plain")
    }

    @Test("A write under `withAnimation(nil)` beside a plain one animates neither")
    func explicitlyUnanimatedScope() {
        let seen = updates { model, _ in
            model.a += 1
            withAnimation(nil) { model.b += 1 }
        }
        #expect(seen.allSatisfy { $0.hasSuffix("plain") }, "\(seen)")
        #expect(seen.last == "a=1 b=1 c=0 plain")
    }

    // MARK: Updates: `@State`

    @Test("`@State`: a plain write, then an animated one")
    func statePlainThenAnimated() {
        let seen = stateUpdates { a, b, _ in
            a.wrappedValue = 1
            withAnimation(fast) { b.wrappedValue = 1 }
        }
        #expect(seen == ["a=1 b=0 plain", "a=1 b=1 fast"])
    }

    @Test("`@State`: an animated write, then a plain one")
    func stateAnimatedThenPlain() {
        let seen = stateUpdates { a, b, _ in
            withAnimation(fast) { b.wrappedValue = 1 }
            a.wrappedValue = 1
        }
        #expect(seen == ["a=0 b=1 fast", "a=1 b=1 plain"])
    }

    @Test("`@State`: two scopes of one animation are one update")
    func stateTwoScopesOfOneAnimation() {
        let seen = stateUpdates { a, b, _ in
            withAnimation(fast) { a.wrappedValue = 1 }
            withAnimation(fast) { b.wrappedValue = 1 }
        }
        #expect(seen == ["a=1 b=1 fast"])
    }

    @Test("`@State`: a plain write, then an empty withAnimation, is drawn plain")
    func statePlainThenEmptyScope() {
        let seen = stateUpdates { a, _, _ in
            a.wrappedValue = 1
            withAnimation(fast) {}
        }
        #expect(seen == ["a=1 b=0 plain"])
    }

    @Test("`@State`: a turn reads its own writes at once, whatever is yet to be drawn")
    func stateReadsItsOwnWrites() {
        let reads = stateUpdates { a, b, log in
            a.wrappedValue = 1
            withAnimation(fast) {
                log.noteUpdate("read \(a.wrappedValue) \(b.wrappedValue)")
                b.wrappedValue = 1
                log.noteUpdate("read \(a.wrappedValue) \(b.wrappedValue)")
            }
        }
        #expect(reads.contains("read 1 0"))
        #expect(reads.contains("read 1 1"))
    }

    // MARK: The picture

    /// Half-way through a one-second slide of B, A — changed plainly beside
    /// it, one body reading both — is already where it was going, in either
    /// order; SwiftUI calls `animatableData`'s setter for B alone
    /// (`txn2.out`, `values`).
    @Test("The animated value moves, the plain one has jumped", arguments: [false, true])
    func eachValueUnderItsOwnChange(animatedFirst: Bool) {
        let readings = Readings()
        let harness = Harness {
            TwoMarksPage(readings: readings) { model in
                if animatedFirst {
                    withAnimation(fast) { model.b = 20 }
                    model.a = 20
                } else {
                    model.a = 20
                    withAnimation(fast) { model.b = 20 }
                }
            }
        }
        expectBJumpsNotA(harness)
    }

    @Test("`@State`: the animated value moves, the plain one has jumped", arguments: [false, true])
    func eachStateValueUnderItsOwnChange(animatedFirst: Bool) {
        expectBJumpsNotA(Harness { TwoStateMarksPage(animatedFirst: animatedFirst) })
    }

    private func expectBJumpsNotA<Page>(_ harness: Harness<Page>) {
        let (startA, startB) = (harness.column(of: "AAA"), harness.column(of: "BBB"))
        #expect(startA != nil && startA == startB, "precondition: the marks are drawn")
        guard let startA, let startB else { return }
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        harness.step(31)
        #expect(harness.column(of: "AAA") == startA + 20, "the plain value animated")
        let halfWay = harness.column(of: "BBB")
        #expect(
            halfWay.map { $0 > startB && $0 < startB + 20 } == true,
            "the animated value is not under way half-way through: \(halfWay.map(String.init) ?? "nowhere")")
        harness.step(45)
        #expect(harness.column(of: "BBB") == startB + 20, "the slide did not end where it was going")
    }

    /// What a clip caught: a panel closed plainly beside a toast's animated
    /// arrival faded with it, and left its frost on the screen until it ended.
    @Test("A view removed plainly goes at once, beside one inserted animated", arguments: [false, true])
    func plainRemovalBesideAnimatedInsertion(toastFirst: Bool) {
        let harness = Harness { PanelAndToastPage(toastFirst: toastFirst) }
        #expect(harness.column(of: "PANEL") != nil, "precondition: the panel is up")
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        harness.step()
        #expect(harness.column(of: "PANEL") == nil, "the panel's removal took the toast's animation")
        harness.step(31)
        #expect(harness.column(of: "PANEL") == nil)
        harness.step(45)
        #expect(harness.column(of: "TOAST") == 0, "the toast did not arrive")
    }

    // MARK: Effects and completions

    private func events(of turn: @escaping @MainActor (Readings, UpdateLog) -> Void, frames: Int = 90) -> [String] {
        let (readings, log) = (Readings(), UpdateLog())
        let harness = Harness { ChangesPage(readings: readings, log: log, turn: turn) }
        log.clear()
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        log.noteEvent("the turn ended")
        harness.step(frames)
        return log.events
    }

    @Test("An action's `onChange` sees the values of its own update, in order")
    func onChangeInOrder() {
        #expect(
            events { model, _ in
                model.a += 1
                withAnimation(fast) { model.b += 1 }
            }.filter { $0.hasPrefix("onChange") } == ["onChange a -> 1 (b=0)", "onChange b -> 1 (a=1)"])
        #expect(
            events { model, _ in
                withAnimation(fast) { model.b += 1 }
                model.a += 1
            }.filter { $0.hasPrefix("onChange") } == ["onChange b -> 1 (a=0)", "onChange a -> 1 (b=1)"])
    }

    /// As Apple documents: no animations are created, so the completion runs
    /// right after the body. The plain change waiting beside it does not hold
    /// it (`txn2.out`), as taking its transaction for that change used to.
    @Test("A completion runs as a scope that writes nothing returns, a plain change waiting or not")
    func completionOfAScopeThatWritesNothing() {
        let seen = events { model, log in
            model.a += 1
            withAnimation(fast) {} completion: { log.noteEvent("completion") }
            log.noteEvent("after the scope")
        }
        #expect(seen.firstIndex(of: "completion") == seen.firstIndex(of: "after the scope").map { $0 - 1 })
    }

    @Test("A completion waits for the animation its scope's write started, a plain change waiting or not")
    func completionOfAScopeThatWrites() {
        let seen = events { model, log in
            model.a += 1
            withAnimation(.linear(duration: 0.1)) { model.b += 20 } completion: { log.noteEvent("completion") }
            log.noteEvent("after the scope")
        }
        let completion = seen.firstIndex(of: "completion")
        let turnEnded = seen.firstIndex(of: "the turn ended")
        #expect(completion != nil, "the completion never ran: \(seen)")
        #expect(completion.flatMap { at in turnEnded.map { at > $0 } } == true, "it ran before the animation: \(seen)")
    }

    // MARK: Where no walk can be made

    /// A view's effect runs during a frame's own walk (`FrameSettling`), where
    /// no other can be made: its changes wait for the walk made again for them,
    /// and share it, under the last transaction (deviation A7).
    @Test("An effect's changes share the walk made again for them")
    func changesInAnEffectShareAWalk() {
        struct AppearsPage: View {
            let readings: Readings
            let log: UpdateLog
            var body: some View {
                Text("\(readings.a) \(readings.b)")
                    .transaction { [readings, log] transaction in
                        let values = "a=\(readings.a) b=\(readings.b)"
                        MainActor.assumeIsolated { log.noteUpdate("\(values) \(spelled(transaction))") }
                    }
                    .onAppear {
                        readings.a = 1
                        withAnimation(fast) { readings.b = 1 }
                    }
            }
        }
        let (readings, log) = (Readings(), UpdateLog())
        _ = Harness { AppearsPage(readings: readings, log: log) }
        #expect(log.updates == ["a=0 b=0 plain", "a=1 b=1 fast", "a=1 b=1 plain"])
    }

    /// `withTransaction` promises no isolation, and a task keeps the app's
    /// render state off the main actor: such a scope walks nothing, and the
    /// frame draws the change.
    @Test("A scope off the main actor walks nothing, and the frame draws what it changed")
    func scopeOffTheMainActor() async {
        final class OffActorReadings: @unchecked Sendable {
            let observed = ObservableValue()
        }
        struct Page: View {
            let readings: OffActorReadings
            var body: some View { Text("value \(readings.observed.value)") }
        }
        let readings = OffActorReadings()
        let harness = Harness { Page(readings: readings) }
        #expect(harness.app.screen.contains { $0.stripped.contains("value 0") })
        let state = harness.app.services.appState
        await Task.detached {
            AmbientApp.$renderState.withValue(state) {
                withAnimation(fast) { readings.observed.value = 1 }
                readings.observed.value = 2
            }
        }.value
        harness.step()
        #expect(harness.app.screen.contains { $0.stripped.contains("value 2") })
    }

    @Test("A loop of scopes walks only so many updates between frames")
    func walksAreBounded() {
        let seen = updates { model, _ in
            for _ in 0..<100 {
                withAnimation(fast) { model.a += 1 }
                withAnimation(slow) { model.b += 1 }
            }
        }
        #expect(seen.count <= UpdateWalks.maximumBetweenFrames + 1, "\(seen.count) updates")
        #expect(seen.last?.hasPrefix("a=100 b=100") == true, "the frame did not draw the last of it: \(seen.last ?? "none")")
    }

    /// The walk before a write to an `@Observable` property is made inside the
    /// registrar's telling: a body it evaluates reads the old value and is not
    /// among those told, so what it kept must not survive it.
    @Test("A body first evaluated just before a plain write draws the value written")
    func bodyFirstEvaluatedBeforeAPlainWrite() {
        struct Page: View {
            @State private var shows = false
            let readings: Readings

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Button("go") {
                        withAnimation(fast) { shows = true }
                        readings.a = 5
                    }
                    Text("reader \(readings.a)")
                    if shows { Inner(readings: readings) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        struct Inner: View {
            let readings: Readings
            var body: some View { Text("inner \(readings.a)").equatable() }
        }
        let readings = Readings()
        let harness = Harness { Page(readings: readings) }
        #expect(harness.app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        harness.step(2)
        #expect(harness.app.screen.contains { $0.stripped.contains("inner 5") })
        #expect(harness.app.screen.contains { $0.stripped.contains("reader 5") })
    }

    // MARK: Every way into a handler

    /// A walk made inside a handler rebuilds the dispatcher's tables and the
    /// focus system's while they are being dispatched from. Each of these is a
    /// way a handler is reached; none must trap, and each must still draw what
    /// its two changes say.
    @Test("A handler reached by a tap, a drag or a hover walks its updates safely")
    func everyPointerPath() {
        struct Page: View {
            let readings: Readings
            let turn: @MainActor () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text("tap").onTapGesture { turn() }
                    Text("drag").gesture(DragGesture(minimumDistance: 0).onChanged { _ in turn() }.onEnded { _ in turn() })
                    Text("hover").onHover { _ in turn() }
                    Button("press") { turn() }
                    Text("\(readings.a) \(readings.b)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        let readings = Readings()
        let harness = Harness(height: 12) {
            Page(readings: readings) {
                readings.a += 1
                withAnimation(fast) { readings.b += 1 }
                readings.a += 1
            }
        }
        func row(_ text: String) -> Int {
            harness.app.screen.firstIndex { $0.stripped.contains(text) } ?? 0
        }
        for (name, column) in [("tap", 1), ("press", 1), ("drag", 1)] {
            let before = readings.b
            let y = row(name)
            _ = harness.app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: y))
            harness.step()
            _ = harness.app.send(MouseEvent(button: .left, phase: .dragged, x: column + 1, y: y))
            harness.step()
            _ = harness.app.send(MouseEvent(button: .left, phase: .released, x: column + 1, y: y))
            harness.step()
            #expect(readings.b > before, "\(name) ran no handler")
        }
        let before = readings.b
        _ = harness.app.send(MouseEvent(button: .none, phase: .moved, x: 1, y: row("hover")))
        harness.step()
        _ = harness.app.send(MouseEvent(button: .none, phase: .moved, x: 1, y: row("press")))
        harness.step()
        #expect(readings.b > before, "hover ran no handler")
        harness.step(90)
        #expect(harness.app.screen.contains { $0.stripped.contains("\(readings.a) \(readings.b)") })
    }

    @Test("A handler reached by a key's press walks its updates safely")
    func everyKeyPath() {
        struct Page: View {
            let readings: Readings
            let turn: @MainActor () -> Void
            @FocusState private var focused: Bool

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Button("shortcut") { turn() }.keyboardShortcut("k", modifiers: .control)
                    Button("press") { turn() }
                    Text("\(readings.a) \(readings.b)")
                }
                .onKeyPress("x") {
                    turn()
                    return .handled
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        let readings = Readings()
        let harness = Harness(height: 12) {
            Page(readings: readings) {
                readings.a += 1
                withAnimation(fast) { readings.b += 1 }
                readings.a += 1
            }
        }
        for event in [KeyEvent(key: .enter), KeyEvent(key: .character("x")), KeyEvent(key: .character("k"), ctrl: true)] {
            let before = readings.b
            _ = harness.app.send(event)
            harness.step()
            #expect(readings.b > before, "\(event) ran no handler")
        }
        harness.step(90)
        #expect(harness.app.screen.contains { $0.stripped.contains("\(readings.a) \(readings.b)") })
    }
}

/// An `@Observable` value with no isolation, for a write off the main actor.
@Observable
private final class ObservableValue: @unchecked Sendable {
    var value = 0
}
