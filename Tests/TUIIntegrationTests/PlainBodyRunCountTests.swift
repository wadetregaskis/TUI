//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainBodyRunCountTests.swift
//
//  How many times a plain composite's `body` runs in a frame, and on whose
//  behalf: the real render loop (`HeadlessApp`), a leaf's `@State` written
//  between frames, each run classified by the stack that made it. The study
//  in Documentation/Working notes/plain-body-memo-study.md reads these lines.
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

// MARK: - The log

/// Every body run in the scene, by tag, with who asked for it. Global rather
/// than a field of the views, so a view under test holds nothing a plain view
/// would not; the tests run one at a time on the main actor and clear it.
@MainActor
private enum BodyLog {
    static var runs: [String: [String]] = [:]
    static var write: (() -> Void)?
    /// Written only when a test says so: the stack walk is slow.
    static var classifying = true

    static func note(_ tag: String) {
        runs[tag, default: []].append(classifying ? cause() : "?")
    }

    /// Who asked: the first framework function that says, reading the stack
    /// from the body outwards.
    private static func cause() -> String {
        let stack = Thread.callStackSymbols
        let underDrawMeasure = stack.contains { $0.contains("measureFixedByRendering") }
        for frame in stack {
            if frame.contains("measureCompositeBody") { return "measure" }
            if frame.contains("evaluateCompositeBody") {
                return underDrawMeasure ? "render-to-measure" : "render"
            }
        }
        return "other"
    }

    static func reset() {
        runs = [:]
        write = nil
    }

    static func take() -> [String: [String]] {
        defer { runs = [:] }
        return runs
    }
}

// MARK: - Counting allocations

#if canImport(Darwin)
/// Allocations, by libmalloc's logging hook: a count, so it needs no quiet box.
/// In a debug build, where generics are not specialised, so the absolute number
/// is not a release build's; what the study reads is the difference between
/// configurations of one binary.
private enum AllocationCount {
    nonisolated(unsafe) static var count = 0
    typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
    nonisolated(unsafe) private static let slot: UnsafeMutablePointer<Logger?>? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
        return symbol.assumingMemoryBound(to: Logger?.self)
    }()

    static func during(_ work: () -> Void) -> Int {
        guard let slot else {
            work()
            return -1
        }
        count = 0
        // MALLOC_LOG_TYPE_ALLOCATE is 2. A realloc logs as both.
        slot.pointee = { type, _, _, _, _, _ in
            if type & 2 != 0 { AllocationCount.count &+= 1 }
        }
        work()
        slot.pointee = nil
        return count
    }
}
#else
private enum AllocationCount {
    static func during(_ work: () -> Void) -> Int {
        work()
        return -1
    }
}
#endif

// MARK: - The views

/// A leaf holding the state a frame's key press writes.
private struct Leaf: View {
    @State private var count = 0

    var body: some View {
        BodyLog.note("leaf")
        BodyLog.write = { count += 1 }
        return Text(verbatim: "leaf \(count)")
    }
}

/// A plain sibling: one small value field.
private struct Plain: View {
    let tag: String

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: tag)
    }
}

private struct WithState: View {
    let tag: String
    @State private var untouched = 0

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: "\(tag) \(untouched)")
    }
}

@Observable
private final class Model {
    var value = 0
}

private struct ReadsObservable: View {
    let tag: String
    let model: Model

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: "\(tag) \(model.value)")
    }
}

private struct WithClosure: View {
    let tag: String
    let action: () -> Void

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: tag)
    }
}

private struct ReadsEnvironment: View {
    let tag: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: "\(tag) \(isEnabled)")
    }
}

private struct HoldsArray: View {
    let tag: String
    let items: [Int]

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: "\(tag) \(items.count)")
    }
}

/// Comparable by the app's own word: the memo that exists today.
private struct EquatablePlain: View, Equatable {
    let tag: String

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: tag)
    }
}

/// A row of a `ForEach` over `Equatable` elements: the other memo that exists.
private struct RowOf: View {
    let tag: String

    var body: some View {
        BodyLog.note(tag)
        return Text(verbatim: tag)
    }
}

/// A nest whose stored value has stable bytes and holds no closure.
private struct PodNest3: View {
    let seed: Int
    var body: some View {
        BodyLog.note("pod3")
        return VStack { Text(verbatim: "3"); PodNest2(seed: seed + 1) }
    }
}
private struct PodNest2: View {
    let seed: Int
    var body: some View {
        BodyLog.note("pod2")
        return VStack { Text(verbatim: "2"); PodNest1(seed: seed + 1) }
    }
}
private struct PodNest1: View {
    let seed: Int
    var body: some View {
        BodyLog.note("pod1")
        return Text(verbatim: "1 \(seed)")
    }
}

/// The same, each level holding a fresh array its parent's body made.
private struct ArrayNest3: View {
    let items: [Int]
    var body: some View {
        BodyLog.note("arr3")
        return VStack { Text(verbatim: "3"); ArrayNest2(items: items + [2]) }
    }
}
private struct ArrayNest2: View {
    let items: [Int]
    var body: some View {
        BodyLog.note("arr2")
        return VStack { Text(verbatim: "2"); ArrayNest1(items: items + [1]) }
    }
}
private struct ArrayNest1: View {
    let items: [Int]
    var body: some View {
        BodyLog.note("arr1")
        return Text(verbatim: "1 \(items.count)")
    }
}

/// A leaf whose `onChange` writes state of its own: its frame is walked again
/// (`FrameSettling`).
private struct SettlingLeaf: View {
    @State private var count = 0
    @State private var derived = 0

    var body: some View {
        BodyLog.note("leaf")
        BodyLog.write = { count += 1 }
        return Text(verbatim: "leaf \(count) \(derived)")
            .onChange(of: count) { _, new in derived = new }
    }
}

/// The state above the siblings, and read by neither of them.
private struct ParentWrites<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var count = 0

    var body: some View {
        BodyLog.note("parent")
        BodyLog.write = { count += 1 }
        return VStack {
            Text(verbatim: "parent \(count)")
            content
        }
    }
}

/// Parent state with the siblings built in its body, as they normally are:
/// their values are made again when it runs.
private struct ParentBuilds: View {
    @State private var count = 0

    var body: some View {
        BodyLog.note("parent")
        BodyLog.write = { count += 1 }
        return VStack {
            Text(verbatim: "parent \(count)")
            Plain(tag: "a")
            Plain(tag: "b")
        }
    }
}

/// A static tree of composites, 64 leaves, as `fan-leaf` in the comparison.
private struct FanThree: View {
    let seed: Int
    var body: some View {
        BodyLog.note("fan")
        return VStack {
            FanTwo(seed: seed &* 4)
            FanTwo(seed: seed &* 4 &+ 1)
            FanTwo(seed: seed &* 4 &+ 2)
            FanTwo(seed: seed &* 4 &+ 3)
        }
    }
}
private struct FanTwo: View {
    let seed: Int
    var body: some View {
        BodyLog.note("fan")
        return HStack {
            FanOne(seed: seed &* 4)
            FanOne(seed: seed &* 4 &+ 1)
            FanOne(seed: seed &* 4 &+ 2)
            FanOne(seed: seed &* 4 &+ 3)
        }
    }
}
private struct FanOne: View {
    let seed: Int
    var body: some View {
        BodyLog.note("fan")
        return HStack {
            FanLeaf(seed: seed &* 4)
            FanLeaf(seed: seed &* 4 &+ 1)
            FanLeaf(seed: seed &* 4 &+ 2)
            FanLeaf(seed: seed &* 4 &+ 3)
        }
    }
}
private struct FanLeaf: View {
    let seed: Int
    var body: some View {
        BodyLog.note("fan")
        return Text(verbatim: "\(seed % 10)")
    }
}

/// Every leaf of the tree changes with the state above it: nothing can be saved.
private struct ChurnPage: View {
    @State private var tick = 0

    var body: some View {
        BodyLog.write = { tick += 1 }
        return VStack {
            ForEach(0..<16, id: \.self) { row in
                ChurnRow(value: row &+ tick)
            }
        }
    }
}

private struct ChurnRow: View {
    let value: Int

    var body: some View {
        BodyLog.note("churn")
        return HStack {
            Text(verbatim: "\(value)")
            Text(verbatim: "\(value &* 2)")
        }
    }
}

// MARK: - The scenarios

private struct ProbeApp<Content: View>: App {
    let content: Content
    init() { fatalError("built with its content") }
    init(content: Content) { self.content = content }
    var body: some Scene { WindowGroup { content } }
}

@MainActor
@Suite("How many times a plain body runs in a frame", .serialized)
struct PlainBodyRunCountTests {
    /// What one frame ran, tag by tag.
    struct Frame {
        let runs: [String: [String]]

        func summary(_ tag: String) -> String {
            let list = runs[tag] ?? []
            var byCause: [String: Int] = [:]
            for cause in list { byCause[cause, default: 0] += 1 }
            let causes = byCause.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            return "\(list.count) (\(causes))"
        }

        func count(_ tag: String) -> Int { runs[tag]?.count ?? 0 }
    }

    struct Report {
        let cold: Frame
        let idle: Frame
        let written: Frame
        let walksOfWritten: Int
    }

    /// A cold frame, a frame with nothing written, then a written one, and a
    /// line a reader can compare against the study's table.
    @discardableResult
    private func run<V: View>(_ name: String, tags: [String], @ViewBuilder _ content: () -> V) -> Report {
        BodyLog.reset()
        let app = HeadlessApp(ProbeApp(content: content()), width: 60, height: 20)
        app.frame(atNanos: 0)
        // A body that wrote or a type first learned reading settles here; the
        // lines below read frames past that.
        app.frame(atNanos: 16_700_000)
        let cold = Frame(runs: BodyLog.take())
        app.frame(atNanos: 33_400_000)
        let idle = Frame(runs: BodyLog.take())
        BodyLog.write?()
        let before = app.effectSettling
        app.frame(atNanos: 50_100_000)
        let written = Frame(runs: BodyLog.take())
        let after = app.effectSettling
        let walks = 1 + (after.rewalks - before.rewalks)
        for tag in tags {
            print(
                "[bodyruns] \(name) \(tag): written=\(written.summary(tag)) idle=\(idle.summary(tag))"
                    + " first-two=\(cold.summary(tag)) walks=\(walks)")
        }
        return Report(cold: cold, idle: idle, written: written, walksOfWritten: walks)
    }

    @Test("Siblings in stacks, and each kind of field")
    func siblings() {
        run("vstack", tags: ["leaf", "a", "b"]) {
            VStack {
                Leaf()
                Plain(tag: "a")
                Plain(tag: "b")
            }
        }
        run("hstack", tags: ["leaf", "a", "b"]) {
            HStack {
                Leaf()
                Plain(tag: "a")
                Plain(tag: "b")
            }
        }
        run("zstack", tags: ["leaf", "a", "b"]) {
            ZStack {
                Leaf()
                Plain(tag: "a")
                Plain(tag: "b")
            }
        }
        run("modifiers", tags: ["padding", "frame", "maxframe", "border", "bg", "fixed"]) {
            VStack {
                Leaf()
                Plain(tag: "padding").padding(1)
                Plain(tag: "frame").frame(width: 20)
                Plain(tag: "maxframe").frame(maxWidth: .infinity)
                Plain(tag: "border").border()
                Plain(tag: "bg").background(Color.red)
                Plain(tag: "fixed").fixedSize()
            }
        }
        run("state", tags: ["s"]) {
            VStack {
                Leaf()
                WithState(tag: "s")
            }
        }
        let model = Model()
        run("observable", tags: ["o"]) {
            VStack {
                Leaf()
                ReadsObservable(tag: "o", model: model)
            }
        }
        run("closure", tags: ["c"]) {
            VStack {
                Leaf()
                WithClosure(tag: "c", action: {})
            }
        }
        run("environment", tags: ["e"]) {
            VStack {
                Leaf()
                ReadsEnvironment(tag: "e")
            }
        }
        run("array", tags: ["r"]) {
            VStack {
                Leaf()
                HoldsArray(tag: "r", items: [1, 2, 3])
            }
        }
    }

    @Test("A parent's write, and the two memos that exist")
    func parentAndMemos() {
        run("parent-content", tags: ["parent", "a", "b"]) {
            ParentWrites {
                Plain(tag: "a")
                Plain(tag: "b")
            }
        }
        run("parent-builds", tags: ["parent", "a", "b"]) { ParentBuilds() }
        run("equatable", tags: ["q"]) {
            VStack {
                Leaf()
                EquatablePlain(tag: "q").equatable()
            }
        }
        run("foreach", tags: ["row-1", "row-2"]) {
            VStack {
                Leaf()
                ForEach([1, 2], id: \.self) { RowOf(tag: "row-\($0)") }
            }
        }
    }

    @Test("Nesting: a value with stable bytes, and one with a fresh address")
    func nesting() {
        run("nest-pod", tags: ["pod3", "pod2", "pod1"]) {
            VStack {
                Leaf()
                PodNest3(seed: 0)
            }
        }
        run("nest-array", tags: ["arr3", "arr2", "arr1"]) {
            VStack {
                Leaf()
                ArrayNest3(items: [3])
            }
        }
    }

    @Test("A frame walked again, and containers that measure otherwise")
    func walksAndContainers() {
        run("settling", tags: ["leaf", "a"]) {
            VStack {
                SettlingLeaf()
                Plain(tag: "a")
            }
        }
        run("scrollview", tags: ["a"]) {
            ScrollView {
                VStack {
                    Leaf()
                    Plain(tag: "a")
                }
            }
        }
        run("lazyvstack", tags: ["a"]) {
            ScrollView {
                LazyVStack {
                    Leaf()
                    Plain(tag: "a")
                }
            }
        }
        run("list", tags: ["a"]) {
            VStack {
                Leaf()
                List {
                    Plain(tag: "a")
                }
            }
        }
        run("overlay", tags: ["base", "over"]) {
            VStack {
                Leaf()
                Plain(tag: "base").overlay { Plain(tag: "over") }
            }
        }
        run("button-label", tags: ["a"]) {
            VStack {
                Leaf()
                Button(action: {}) { Plain(tag: "a") }
            }
        }
        run("viewthatfits", tags: ["a", "b"]) {
            VStack {
                Leaf()
                ViewThatFits {
                    Plain(tag: "a")
                    Plain(tag: "b")
                }
            }
        }
        run("group-hstack", tags: ["a"]) {
            HStack {
                Leaf()
                Group { Plain(tag: "a") }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One written frame's allocations and body runs, past the warm-up, with no
    /// stack walks to count.
    private func price<V: View>(_ name: String, tag: String, @ViewBuilder _ content: () -> V) {
        BodyLog.reset()
        BodyLog.classifying = false
        defer { BodyLog.classifying = true }
        let app = HeadlessApp(ProbeApp(content: content()), width: 100, height: 30)
        var nanos: Int64 = 0
        for _ in 0..<4 {
            app.frame(atNanos: nanos)
            nanos += 16_700_000
        }
        _ = BodyLog.take()
        var counts: [Int] = []
        var bodies: [Int] = []
        for _ in 0..<5 {
            BodyLog.write?()
            let frameAt = nanos
            counts.append(AllocationCount.during { app.frame(atNanos: frameAt) })
            bodies.append(BodyLog.take()[tag]?.count ?? 0)
            nanos += 16_700_000
        }
        let cache = app.renderCache
        print(
            "[price] \(name): allocations \(counts) bodies(\(tag)) \(bodies)"
                + " stores=\(cache.stats.stores) hits=\(cache.stats.hits) misses=\(cache.stats.misses)"
                + " subtreeClears=\(cache.stats.subtreeClears)")
    }

    @Test("What a written frame allocates")
    func prices() {
        price("fan64-leaf", tag: "fan") {
            VStack {
                Leaf()
                FanThree(seed: 1)
            }
        }
        price("churn16", tag: "churn") { ChurnPage() }
        price("parent-builds", tag: "a") { ParentBuilds() }
    }
}
