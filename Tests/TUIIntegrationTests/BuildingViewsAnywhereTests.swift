//  🖥️ TUI — A Terminal UI framework for Swift
//  BuildingViewsAnywhereTests.swift
//
//  A view is a value, built anywhere, as in SwiftUI; `body` and drawing stay on
//  the main actor. Every helper here is nonisolated, so that this file compiling
//  is itself the check on the isolation of what it names.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI

@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Free functions

private func row(_ title: String, count: Int) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(verbatim: "\(count)")
    }
    .padding(.horizontal, 1)
}

private func commonModifiers() -> some View {
    Text("x").padding().border(.red).hidden().id(1).frame(width: 3).background(.red).opacity(0.5).disabled(true).bold()
}

private func controls(_ on: Binding<Bool>, _ text: Binding<String>, _ value: Binding<Double>) -> some View {
    VStack {
        Toggle("t", isOn: on)
        TextField("n", text: text)
        Slider(value: value, in: 0...1)
        Label("l", systemImage: "star")
        Section("s") { Text("x") }
        ScrollView { Text("y") }
        Group { Text("z") }
        AnyView(Text("a"))
        Divider()
        Spacer()
    }
}

private func containers(_ items: [Int]) -> some View {
    VStack {
        ForEach(items, id: \.self) { Text(verbatim: "\($0)") }
        List(items, id: \.self) { Text(verbatim: "\($0)") }
        NavigationStack { Text("n").navigationTitle("t") }
    }
}

private func presentation(_ isPresented: Binding<Bool>) -> some View {
    Text("x")
        .sheet(isPresented: isPresented) { Text("s") }
        .alert("a", isPresented: isPresented) { Button("ok") {} }
}

private func handlers(_ value: Int, _ action: @escaping () -> Void) -> some View {
    Text("x")
        .onChange(of: value) { _, _ in action() }
        .onAppear(perform: action)
        .onTapGesture(perform: action)
        .task {}
        .gesture(TapGesture().onEnded { action() })
}

private func erased(_ isCompact: Bool) -> AnyView {
    if isCompact {
        return AnyView(Text("Compact"))
    }
    return AnyView(VStack { Text("Full"); Text("Layout") })
}

private enum Helpers {
    static func titled(_ title: String) -> some View {
        VStack { Text(title).bold() }
    }
}

private final class NotOnTheMainActor {
    func view() -> some View { Text("x").foregroundStyle(.red) }
}

private actor OwnActor {
    func text() -> Text { Text("from an actor") }
}

// MARK: - A button's action

@MainActor
private final class Counter {
    var count = 0
    func increment() { count += 1 }
}

private func button(_ counter: Counter) -> Button {
    Button("Add") { counter.increment() }
}

private func buttonTitled(_ title: String, _ counter: Counter) -> Button {
    Button(title) { counter.increment() }
}

private func button(action: @escaping () -> Void) -> Button {
    Button("Add", action: action)
}

// MARK: - A view of one's own

private struct Titled<Content: View> {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
}

extension Titled: View {
    var body: some View {
        VStack {
            Text(title)
            content
        }
    }
}

private func ownView() -> some View {
    Titled(title: "T") { Text("x") }
}

// MARK: - Tests

@MainActor
@Suite("Views built off the main actor")
struct BuildingViewsAnywhereTests {
    private func drawn(_ view: some View) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 10)).lines.joined(separator: "\n").stripped
    }

    @Test("What a free function builds draws as it would in a body")
    func freeFunction() {
        #expect(drawn(row("Apples", count: 3)).contains("Apples"))
        #expect(drawn(row("Apples", count: 3)).contains("3"))
        #expect(drawn(erased(true)).contains("Compact"))
        #expect(drawn(Helpers.titled("Heading")).contains("Heading"))
        #expect(drawn(ownView()).contains("T"))
        _ = commonModifiers()
        _ = controls(.constant(true), .constant(""), .constant(0))
        _ = containers([1])
        _ = presentation(.constant(false))
        _ = handlers(1) {}
        _ = NotOnTheMainActor().view()
    }

    @Test("A Text crosses from a detached task and from an actor")
    func crossing() async {
        let detached = await Task.detached { Text("from a task") }.value
        #expect(drawn(detached).contains("from a task"))
        let fromActor = await OwnActor().text()
        #expect(drawn(fromActor).contains("from an actor"))
    }

    @Test("A static Text is shared across isolation")
    func staticText() {
        enum Titles { static let title = Text("static") }
        #expect(drawn(Titles.title).contains("static"))
    }

    @Test("A button built in a free function runs its action on a press")
    func pressing() {
        let counter = Counter()
        button(counter).action()
        buttonTitled("Add", counter).action()
        #expect(counter.count == 2)
        var ran = false
        button { ran = true }.action()
        #expect(ran)
    }

    @Test("Many tasks making one keyed Text make equal ones")
    func concurrentKeys() async {
        let texts = await withTaskGroup(of: [Text].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    (0..<200).map { _ in Text("the same key **bold**") }
                }
            }
            var all: [Text] = []
            for await made in group { all += made }
            return all
        }
        #expect(texts.count == 1_600)
        #expect(Set(texts.map { drawn($0) }).count == 1)
        #expect(texts.allSatisfy { $0 == texts[0] })
    }
}
