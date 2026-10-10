//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewModifierTests.swift
//
//  SwiftUI's `ViewModifier`: a `body(content:)` that composes views around the
//  view it is applied to. Each test is SwiftUI source, as SwiftUI's own
//  documentation writes it, and what it must draw.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Brackets its content: the shape of nearly every custom modifier.
private struct Bracketed: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Text("[")
            content
            Text("]")
        }
    }
}

/// Prefixes its content with a marker — composes with `Bracketed`.
private struct Starred: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Text("*")
            content
        }
    }
}

extension View {
    fileprivate func bracketed() -> some View {
        modifier(Bracketed())
    }
}

/// Hands its state's binding out each time its body is built, so a test can
/// write to the state between frames.
@MainActor
private final class BindingTap {
    var binding: Binding<Int>?
}

/// A modifier with state of its own.
private struct Counted: ViewModifier {
    let tap: BindingTap
    @State private var count = 0

    func body(content: Content) -> some View {
        tap.binding = $count
        return HStack(spacing: 0) {
            content
            Text(verbatim: " \(count)")
        }
    }
}

private struct Greeting: EnvironmentKey {
    static let defaultValue = "hello"
}

extension EnvironmentValues {
    fileprivate var greeting: String {
        get { self[Greeting.self] }
        set { self[Greeting.self] = newValue }
    }
}

/// A modifier that reads the environment.
private struct Greeted: ViewModifier {
    @Environment(\.greeting) private var greeting

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: greeting + " ")
            content
        }
    }
}

/// A modifier that animates its one number.
private struct Indent: ViewModifier, Animatable {
    var columns: Int

    var animatableData: Double {
        get { Double(columns) }
        set { columns = Int(newValue.rounded()) }
    }

    func body(content: Content) -> some View {
        content.padding(.leading, columns)
    }
}

@MainActor
@Suite("ViewModifier")
struct ViewModifierTests {

    private func lines<V: View>(_ view: V, context: RenderContext? = nil) -> [String] {
        let context = context ?? makeRenderContext(width: 20, height: 2)
        return renderToBuffer(view, context: context).lines.map {
            $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression)
        }
    }

    @Test("A modifier's body is built around the view it is applied to")
    func composes() {
        #expect(lines(Text("hi").modifier(Bracketed())).first == "[hi]")
        #expect(lines(Text("hi").bracketed()).first == "[hi]")
    }

    @Test("Modifiers nest, the later one outermost")
    func nests() {
        #expect(lines(Text("hi").modifier(Bracketed()).modifier(Starred())).first == "*[hi]")
    }

    @Test("concat applies the first modifier, then the second around it")
    func concatenates() {
        #expect(lines(Text("hi").modifier(Bracketed().concat(Starred())))
            == lines(Text("hi").modifier(Bracketed()).modifier(Starred())))
    }

    @Test("The empty modifier leaves the view as it is")
    func emptyModifier() {
        #expect(lines(Text("hi").modifier(EmptyModifier())) == lines(Text("hi")))
        #expect(lines(Text("hi").modifier(EmptyModifier.identity)) == lines(Text("hi")))
    }

    /// The view is built afresh for each frame, as an app's `body` builds it:
    /// a reused value would carry its state along in the value itself and pass
    /// whether or not the state was ever bound to storage.
    @Test("A modifier's @State survives from frame to frame")
    func stateSurvives() {
        let context = makeRenderContext(width: 20, height: 2)
        let tap = BindingTap()
        func frame() -> [String] { lines(Text("n").modifier(Counted(tap: tap)), context: context) }
        #expect(frame().first == "n 0")
        tap.binding?.wrappedValue = 7
        #expect(frame().first == "n 7", "the write reached the stored state")
    }

    @Test("Two views given one modifier type keep their own state")
    func stateIsPerApplication() {
        let context = makeRenderContext(width: 20, height: 2)
        let first = BindingTap()
        let second = BindingTap()
        func frame() -> [String] {
            lines(VStack {
                Text("a").modifier(Counted(tap: first))
                Text("b").modifier(Counted(tap: second))
            }, context: context)
        }
        _ = frame()
        first.binding?.wrappedValue = 3
        #expect(frame() == ["a 3", "b 0"])
    }

    @Test("A modifier reads the environment where it is applied")
    func readsEnvironment() {
        #expect(lines(Text("you").modifier(Greeted())).first == "hello you")
        #expect(lines(Text("you").modifier(Greeted()).environment(\.greeting, "hi"))
            .first == "hi you")
    }

    /// Only the frame that carries the change is animated, as in the app:
    /// the frames after it draw the animation with an empty transaction. That
    /// matters here because the modifier's body is itself an animatable
    /// `.padding`, which would otherwise start an animation of its own toward
    /// each intermediate value.
    @Test("An Animatable modifier animates its data")
    func animates() {
        var context = makeRenderContext(width: 30, height: 2)
        context.environment.canAnimate = true
        func indent(_ columns: Int, atMillis millis: Int, animated: Bool = false) -> Int {
            context.environment.transaction = Transaction(animation: animated ? .linear(duration: 1) : nil)
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let line = lines(Text("ab").modifier(Indent(columns: columns)), context: context)[0]
            return line.count - line.drop(while: { $0 == " " }).count
        }
        _ = indent(0, atMillis: 0)
        #expect(indent(10, atMillis: 0, animated: true) == 0)
        #expect(indent(10, atMillis: 500) == 5)
        #expect(indent(10, atMillis: 1000) == 10)
    }
}

/// Resolves to a modifier with a body of its own.
private struct ResolvesToBrackets: EnvironmentalModifier {
    func resolve(in environment: EnvironmentValues) -> Bracketed {
        Bracketed()
    }
}

/// Resolves to an indent as wide as the greeting, so the environment's value
/// is visible in what is drawn.
private struct IndentByGreeting: EnvironmentalModifier {
    func resolve(in environment: EnvironmentValues) -> Indent {
        Indent(columns: environment.greeting.count)
    }
}

@MainActor
@Suite("EnvironmentalModifier")
struct EnvironmentalModifierTests {

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 1))
            .lines.first?.stripped ?? ""
    }

    @Test("An environmental modifier is resolved in the environment where it is applied")
    func resolvesWhereApplied() {
        #expect(line(Text("x").modifier(IndentByGreeting())).hasPrefix("     x"), "hello is five")
        #expect(line(Text("x").modifier(IndentByGreeting()).environment(\.greeting, "hi"))
            .hasPrefix("  x"), "hi is two")
    }

    @Test("What it resolves to is applied as any modifier is")
    func appliesResolved() {
        #expect(line(Text("x").modifier(ResolvesToBrackets())).hasPrefix("[x]"))
    }
}
