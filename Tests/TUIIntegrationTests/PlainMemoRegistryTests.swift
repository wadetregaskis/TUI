//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainMemoRegistryTests.swift
//
//  The audit `memo-verifier-blind-to-side-effects` asks for, as a test: every
//  kind of per-frame registration a view can make, inside a plain composite the
//  memo serves, against the same page with the memo off. The render verifier
//  compares buffers, and a served frame that drops a registration draws exactly
//  the same picture, so this compares the registries and what the app does: the
//  key, mouse, shortcut and drag tables, the focus ring, and a run of input.
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

/// What each copy of a page does, and how to write its state.
@MainActor
private final class Copy {
    var leafWrite: (() -> Void)?
    var pageWrite: (() -> Void)?
    var log: [String] = []
    var bodies = 0
}

private struct RegistryApp<Content: View>: App {
    let content: Content
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its content") }
    init(content: Content) { self.content = content }
    var body: some Scene { WindowGroup { content } }
}

private struct Leaf: View {
    let copy: Copy
    @State private var count = 0
    var body: some View {
        copy.leafWrite = { count += 1 }
        return Text(verbatim: "leaf \(count)")
    }
}

/// The composite the memo is on: its content is built by its body, as a page's
/// would be, with a field that does not change.
private struct Holder<Content: View>: View {
    let copy: Copy
    let tag: Int
    @ViewBuilder let content: (Copy) -> Content
    var body: some View {
        copy.bodies += 1
        return content(copy)
    }
}

private struct Page<Content: View>: View {
    let copy: Copy
    @ViewBuilder let content: (Copy) -> Content
    @State private var count = 0
    var body: some View {
        copy.pageWrite = { count += 1 }
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "page \(count)")
            Leaf(copy: copy)
            Holder(copy: copy, tag: 1, content: content)
        }
    }
}

/// Everything per-frame a served subtree must have made again.
private struct Registries: Equatable {
    let screen: [String]
    let focused: String?
    let keyHandlers: Int
    let mouseHandlers: Int
    let shortcuts: Int
    let dropTargets: Int
    let autoScrollZones: Int
    let reorderHosts: Int

    @MainActor
    init(_ app: HeadlessApp) {
        screen = app.screen
        focused = app.focusedID
        keyHandlers = app.services.keyEventDispatcher.handlerCount
        mouseHandlers = app.services.mouseEventDispatcher.handlerCount
        shortcuts = app.services.keyboardShortcuts.registrationCount
        dropTargets = app.services.dragAndDropSession.targets.count
        autoScrollZones = app.services.dragAndDropSession.autoScrollZones.count
        reorderHosts = app.services.dragAndDropSession.reorderHosts.count
    }
}

private enum Tag: Hashable { case one, two }

private struct FocusBinder: View {
    let copy: Copy
    @FocusState private var focus: Tag?
    var body: some View {
        VStack {
            Button("first") { copy.log.append("first") }.focused($focus, equals: .one)
            Button("second") { copy.log.append("second") }.focused($focus, equals: .two)
        }
        .defaultFocus($focus, .two)
    }
}

private struct ReadsFocusedValue: View {
    @FocusedValue(\.plainMemoProbe) private var value
    var body: some View { Text(verbatim: "focused \(value ?? "none")") }
}

extension FocusedValues {
    fileprivate var plainMemoProbe: String? {
        get { self[PlainMemoProbeKey.self] }
        set { self[PlainMemoProbeKey.self] = newValue }
    }
}

private struct PlainMemoProbeKey: FocusedValueKey {
    typealias Value = String
}

private struct WritesPreference: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

@MainActor
@Suite("A served plain composite makes every per-frame registration again", .serialized)
struct PlainMemoRegistryTests {
    /// Runs a page with the memo off and on, through writes beside it and above
    /// it and a run of keys, comparing the registries and the log at each step.
    private func compare<Content: View>(
        _ name: String, keys: [KeyEvent] = [KeyEvent(key: .tab), KeyEvent(key: .tab), KeyEvent(key: .enter)],
        expectServed: Bool = true, @ViewBuilder _ content: @escaping (Copy) -> Content
    ) {
        func run(on: Bool, step: (Int, Copy, HeadlessApp) -> Void) -> Int {
            let copy = Copy()
            let app = HeadlessApp(RegistryApp(content: Page(copy: copy, content: content)), width: 60, height: 20)
            app.renderCache.plainMemo.isOn = on
            var nanos: Int64 = 0
            var index = 0
            func frame() {
                app.frame(atNanos: nanos)
                nanos += 16_700_000
                step(index, copy, app)
                index += 1
            }
            for _ in 0..<3 { frame() }
            for _ in 0..<3 {
                copy.leafWrite?()
                frame()
            }
            for key in keys {
                _ = app.send(key)
                copy.leafWrite?()
                frame()
            }
            copy.pageWrite?()
            frame()
            copy.leafWrite?()
            frame()
            return app.renderCache.rowWork.servedDrawing
        }

        var off: [(Registries, [String])] = []
        _ = run(on: false) { _, copy, app in off.append((Registries(app), copy.log)) }
        var mismatches = 0
        let served = run(on: true) { index, copy, app in
            let seen = Registries(app)
            guard index < off.count, mismatches == 0 else { return }
            if seen != off[index].0 || copy.log != off[index].1 {
                mismatches += 1
                Issue.record("\(name), step \(index): on \(seen), \(copy.log); off \(off[index].0), \(off[index].1)")
            }
        }
        if expectServed {
            #expect(served > 0, "\(name): nothing was served, so nothing was tested")
        }
    }

    @Test("Key handlers") func keyHandlers() {
        compare("onKeyEvent", keys: [KeyEvent(character: "k")]) { copy in
            Text("x").onKeyEvent(.character("k")) { copy.log.append("k") }
        }
        compare("onKeyPress", keys: [KeyEvent(character: "k")]) { copy in
            Button("b") {}.onKeyPress("k") {
                copy.log.append("k")
                return .handled
            }
        }
    }

    @Test("Status bar items") func statusBar() {
        compare("statusBarItems", keys: [KeyEvent(character: "w")]) { copy in
            Text("x").statusBarItems {
                StatusBarItem(shortcut: "w", label: "w") { copy.log.append("w") }
            }
        }
    }

    @Test("Focus: controls, sections, default focus, a binding") func focus() {
        compare("buttons") { copy in
            VStack {
                Button("a") { copy.log.append("a") }
                Button("b") { copy.log.append("b") }
            }
        }
        compare("focusSection") { copy in
            VStack {
                Button("a") { copy.log.append("a") }.focusSection("one")
                Button("b") { copy.log.append("b") }.focusSection("two")
            }
        }
        compare("defaultFocus and focused") { FocusBinder(copy: $0) }
        compare("focusable and onKeyPress", keys: [KeyEvent(key: .tab), KeyEvent(character: "k")]) { copy in
            Text("x").focusable().onKeyPress("k") {
                copy.log.append("k")
                return .handled
            }
        }
    }

    @Test("Keyboard shortcuts") func shortcuts() {
        compare("keyboardShortcut", keys: [KeyEvent(key: .character("s"), ctrl: true)]) { copy in
            Button("save") { copy.log.append("save") }.keyboardShortcut("s", modifiers: .control)
        }
    }

    @Test("Mouse: tap, hover, drag and drop, a context menu") func mouse() {
        compare("onTapGesture") { copy in Text("x").onTapGesture { copy.log.append("tap") } }
        compare("onHover") { copy in Text("x").onHover { _ in copy.log.append("hover") } }
        compare("draggable") { _ in Text("x").draggable("payload") }
        compare("dropDestination") { copy in
            Text("x").dropDestination(for: String.self) { _, _ in
                copy.log.append("drop")
                return true
            }
        }
        compare("contextMenu") { copy in
            Button("x") {}.contextMenu { Button("m") { copy.log.append("m") } }
        }
        compare("pointerStyle") { _ in Text("x").pointerStyle(.link) }
        compare("help") { _ in Button("x") {}.help("words") }
    }

    @Test("Values and preferences read or published per frame", arguments: [true])
    func values(_: Bool) {
        compare("focusedValue", expectServed: false) { _ in
            VStack {
                Button("a") {}.focusedValue(\.plainMemoProbe, "a")
                ReadsFocusedValue()
            }
        }
        compare("preference", expectServed: false) { copy in
            Text("x").preference(key: WritesPreference.self, value: 1)
                .onPreferenceChange(WritesPreference.self) { copy.log.append("pref \($0)") }
        }
    }

    @Test("Lifecycle: appear, task, change") func lifecycle() {
        compare("onAppear", expectServed: false) { copy in Text("x").onAppear { copy.log.append("appear") } }
        compare("onDisappear", expectServed: false) { copy in Text("x").onDisappear { copy.log.append("disappear") } }
        compare("onChange", expectServed: false) { copy in
            Text("x").onChange(of: 1) { copy.log.append("change") }
        }
    }

    @Test("Geometry: readers, a coordinate space, a matched effect") func geometry() {
        compare("GeometryReader", expectServed: false) { _ in
            GeometryReader { proxy in Text(verbatim: "w \(proxy.size.width)") }
        }
        compare("onGeometryChange", expectServed: false) { copy in
            Text("x").onGeometryChange(for: Int.self, of: { Int($0.size.width) }, action: { copy.log.append("g \($0)") })
        }
        compare("coordinateSpace") { _ in Text("x").coordinateSpace(.named("space")) }
        compare("matchedGeometryEffect", expectServed: false) { _ in MatchedProbe() }
    }

    @Test("Containers: a list, a scroll view, a picker, a toggle, a field") func containers() {
        compare("List") { copy in
            List {
                Button("a") { copy.log.append("a") }
                Text("b")
            }
        }
        compare("ScrollView") { _ in
            ScrollView { VStack { ForEach(0..<30) { Text(verbatim: "\($0)") } } }
        }
        compare("Toggle") { _ in Toggle("t", isOn: .constant(true)) }
        compare("TextField", keys: [KeyEvent(key: .tab), KeyEvent(character: "k")]) { _ in
            TextField("name", text: .constant(""))
        }
        compare("Picker") { _ in
            Picker("p", selection: .constant(1)) {
                Text("one").tag(1)
                Text("two").tag(2)
            }
        }
        compare("Menu") { copy in Menu("m") { Button("i") { copy.log.append("i") } } }
    }

    @Test("Presentations that are not up, chrome declared from below") func presentation() {
        compare("sheet") { _ in Text("x").sheet(isPresented: .constant(false)) { Text("s") } }
        compare("alert") { _ in Text("x").alert("t", isPresented: .constant(false)) { Button("OK") {} } }
        compare("toolbar", expectServed: false) { copy in
            Text("x").toolbar { ToolbarItem { Button("t") { copy.log.append("t") } } }
        }
        compare("toolbarVisibility", expectServed: false) { _ in Text("x").toolbarVisibility(.hidden, for: .windowToolbar) }
        compare("navigationTitle", expectServed: false) { _ in Text("x").navigationTitle("title") }
        compare("refreshable") { copy in
            let log: @MainActor @Sendable () -> Void = { copy.log.append("refresh") }
            Text("x").refreshable { log() }
        }
    }

    @Test("What moves on its own keeps moving") func time() {
        compare("ProgressView", expectServed: false) { _ in ProgressView() }
        compare("TimelineView", expectServed: false) { _ in
            TimelineView(.periodic(from: .now, by: 1)) { context in Text(verbatim: "\(context.date.timeIntervalSince1970 > 0)") }
        }
    }
}

private struct MatchedProbe: View {
    @Namespace private var space
    var body: some View { Text("x").matchedGeometryEffect(id: 1, in: space) }
}
