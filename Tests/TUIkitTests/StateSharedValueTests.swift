//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateSharedValueTests.swift
//
//  A `@State` keeps its storage box behind a reference, `StateBacking`, which
//  the property walk binds to the box kept for the view's identity just
//  before each body. Every copy of a `State` value shares that reference. So
//  one value rendered at two identities — a view value placed twice, or one
//  property value handed to two child views — was pointed at the second
//  identity's box last, and a binding or closure made in the first view's
//  body read and wrote the second view's state (DYNV bug 1).
//
//  SwiftUI installs each view's state into that view's own copy, so the two
//  stay apart (measured on macOS 15.8.1, SwiftUI 6.5.4, offscreen
//  NSHostingView: session notes DYNV/probe/dv.swift, cases `twice` and
//  `value`, output dv.out). TUIkit now does the same: a place whose copy
//  holds a backing bound to another place is given a backing of its own. An
//  `@Environment`'s box, shared the same way, is given one for each place
//  too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What the bodies hand out.
@MainActor
private final class SharedValueTaps {
    /// The first binding any body handed out.
    var first: Binding<Int>?
    /// Each child's binding, by its name.
    var bindings: [String: Binding<Int>] = [:]
}

/// A view with a `@State` of its own, nothing nested.
private struct PlainCounter: View {
    let taps: SharedValueTaps
    @State private var count = 0

    var body: some View {
        if taps.first == nil { taps.first = $count }
        return Text(verbatim: "count \(count)")
    }
}

/// One view value placed twice: two independent counters in SwiftUI.
private struct SameViewTwice: View {
    let taps: SharedValueTaps

    var body: some View {
        let counter = PlainCounter(taps: taps)
        return VStack {
            counter
            counter
        }
    }
}

/// An app property holding a `@State`.
private struct KeptCount: DynamicProperty {
    @State var count = 0
}

private struct KeptCountChild: View {
    let name: String
    let kept: KeptCount
    let taps: SharedValueTaps

    var body: some View {
        taps.bindings[name] = kept.$count
        return Text(verbatim: "\(name) \(kept.count)")
    }
}

/// One property value, made by the parent and handed to two children.
private struct TwoChildrenOneValue: View {
    let taps: SharedValueTaps

    var body: some View {
        let kept = KeptCount()
        return VStack {
            KeptCountChild(name: "a", kept: kept, taps: taps)
            KeptCountChild(name: "b", kept: kept, taps: taps)
        }
    }
}

private struct SharedAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var sharedAccent: String {
        get { self[SharedAccent.self] }
        set { self[SharedAccent.self] = newValue }
    }
}

/// What each placement's closure reads, by the environment it drew under.
@MainActor
private final class AccentReaders {
    var readers: [String: () -> String] = [:]
}

/// A view reading the environment, handing out a closure that reads it.
private struct AccentReader: View {
    let readers: AccentReaders
    @Environment(\.sharedAccent) private var accent

    var body: some View {
        let reader = self
        readers.readers[accent] = { reader.accent }
        return Text(verbatim: accent)
    }
}

/// One reader value placed under two environments.
private struct SameReaderTwice: View {
    let readers: AccentReaders

    var body: some View {
        let reader = AccentReader(readers: readers)
        return VStack {
            reader.environment(\.sharedAccent, "red")
            reader.environment(\.sharedAccent, "blue")
        }
    }
}

@MainActor
@Suite("@State in a value rendered at two places")
struct StateSharedValueTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// SwiftUI: the binding the first placement handed out writes the first
    /// (dv.out, `twice`). TUIkit drew `["count 0", "count 5"]`.
    @Test("One view value placed twice keeps two counters, and the first one's binding writes the first")
    func sameViewTwice() {
        let context = makeRenderContext(width: 20, height: 2)
        let taps = SharedValueTaps()
        #expect(lines(SameViewTwice(taps: taps), context: context) == ["count 0", "count 0"])
        taps.first?.wrappedValue = 5
        #expect(lines(SameViewTwice(taps: taps), context: context) == ["count 5", "count 0"])
    }

    /// SwiftUI: child a's binding writes child a (dv.out, `value`). TUIkit
    /// drew `["a 0", "b 5"]`.
    @Test("A property value handed to two child views: the first child's binding writes the first child")
    func oneValueTwoChildren() {
        let context = makeRenderContext(width: 20, height: 2)
        let taps = SharedValueTaps()
        #expect(lines(TwoChildrenOneValue(taps: taps), context: context) == ["a 0", "b 0"])
        taps.bindings["a"]?.wrappedValue = 5
        #expect(lines(TwoChildrenOneValue(taps: taps), context: context) == ["a 5", "b 0"])
    }

    /// The `@Environment` twin: the box an `@Environment` resolves into was
    /// shared by every copy, so a closure made in the first placement's body
    /// read the second placement's environment. Each place's copy now gets a
    /// box of its own, as SwiftUI resolves each place's copy.
    @Test("One view value placed under two environments: each placement's closure reads its own")
    func sameReaderTwice() {
        let context = makeRenderContext(width: 20, height: 2)
        let readers = AccentReaders()
        #expect(lines(SameReaderTwice(readers: readers), context: context) == ["red", "blue"])
        #expect(readers.readers["red"]?() == "red")
        #expect(readers.readers["blue"]?() == "blue")
    }
}
