//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationDestinationLookupTests.swift
//
//  Which `navigationDestination(for:)` a pushed value finds: the one for the
//  type it was pushed as, as SwiftUI's does (measured,
//  `Tools/SwiftUIProbes/Navigation identities (H-69)/navident.out`, case 2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUINavigation
import TUITesting
@testable import TUITestSupport

/// A `Hashable` class, and a subclass of it.
private class Shape: Hashable, CustomStringConvertible {
    let id: Int
    init(_ id: Int) { self.id = id }
    static func == (lhs: Shape, rhs: Shape) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var description: String { "\(type(of: self))(\(id))" }
}
private final class Circle: Shape {}

/// The path the pages read and the tests write.
@Observable
private final class PathModel {
    var path = NavigationPath()
}

@MainActor
@Suite("NavigationStack: the destination a pushed value finds")
struct NavigationDestinationLookupTests {

    /// Which type the root registers a destination for.
    private enum Registered { case shape, circle }

    private struct Root: View {
        let registered: Registered
        var body: some View {
            switch registered {
            case .shape:
                Text("root").navigationDestination(for: Shape.self) { Text(verbatim: "Shape destination for \($0)") }
            case .circle:
                Text("root").navigationDestination(for: Circle.self) { Text(verbatim: "Circle destination for \($0)") }
            }
        }
    }

    private func screen(_ path: NavigationPath, registered: Registered) -> String {
        var path = path
        let app = TestApp(width: 60, height: 6) {
            NavigationStack(path: Binding(get: { path }, set: { path = $0 })) { Root(registered: registered) }
        }
        return app.screen.lines.joined(separator: "\n")
    }

    @Test("A subclass appended to a NavigationPath as its superclass shows the superclass's destination")
    func appendedAsSuperclass() {
        var path = NavigationPath()
        path.append(Circle(7) as Shape)
        let shown = screen(path, registered: .shape)
        #expect(shown.contains("Shape destination for Circle(7)"), "\(shown)")
    }

    @Test("A subclass appended as itself shows no superclass's destination")
    func appendedAsSubclass() {
        var path = NavigationPath()
        path.append(Circle(7))
        let shown = screen(path, registered: .shape)
        #expect(!shown.contains("destination"), "\(shown)")
    }

    @Test("A subclass pushed as its superclass shows no destination registered for the subclass")
    func registeredForSubclass() {
        var path = NavigationPath()
        path.append(Circle(7) as Shape)
        let shown = screen(path, registered: .circle)
        #expect(!shown.contains("destination"), "\(shown)")
    }

    @Test("A typed path of the superclass holding a subclass shows the superclass's destination")
    func typedPath() {
        var path: [Shape] = [Circle(7)]
        let app = TestApp(width: 60, height: 6) {
            NavigationStack(path: Binding(get: { path }, set: { path = $0 })) { Root(registered: .shape) }
        }
        let shown = app.screen.lines.joined(separator: "\n")
        #expect(shown.contains("Shape destination for Circle(7)"), "\(shown)")
        #expect(path.count == 1)
    }

    @Test("A link whose value is typed as the superclass shows the superclass's destination")
    func linkTypedAsSuperclass() {
        let app = TestApp(width: 60, height: 6) {
            NavigationStack {
                NavigationLink("open", value: Circle(7) as Shape)
                    .navigationDestination(for: Shape.self) { Text(verbatim: "Shape destination for \($0)") }
            }
        }
        _ = app.screen
        _ = app.press(.enter)
        let shown = app.screen.lines.joined(separator: "\n")
        #expect(shown.contains("Shape destination for Circle(7)"), "\(shown)")
    }

    // MARK: Two registrations of one type

    /// `String` registered on every screen an `Int` pushes, and on the root
    /// too when `onRoot`.
    private struct Strings: View {
        let model: PathModel
        let onRoot: Bool
        var body: some View {
            NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
                if onRoot {
                    screens.navigationDestination(for: String.self) { Text("root's String \($0)") }
                } else {
                    screens
                }
            }
        }
        private var screens: some View {
            Text("root").navigationDestination(for: Int.self) { number in
                Text("int \(number)").navigationDestination(for: String.self) { Text("int \(number)'s String \($0)") }
            }
        }
    }

    private func shown(_ app: TestApp) -> String {
        app.screen.lines.joined(separator: "\n")
    }

    @Test("Of two screens registering one type, the one closest to the root is used, as SwiftUI's is")
    func closestToTheRootWins() {
        // SwiftUI warns and uses the one declared closest to the root
        // (navident.out, case 3A). A buried screen does not render, so the
        // registration of the screen above it, made last, used to win.
        let model = PathModel()
        let app = TestApp(width: 60, height: 6) { Strings(model: model, onRoot: false) }
        model.path.append(1)
        _ = app.screen
        model.path.append(2)
        _ = app.screen
        model.path.append("x")
        #expect(shown(app).contains("int 1's String x"), "\(shown(app))")
    }

    @Test("The root's registration is used over a pushed screen's")
    func rootWins() {
        let model = PathModel()
        let app = TestApp(width: 60, height: 6) { Strings(model: model, onRoot: true) }
        model.path.append(1)
        _ = app.screen
        model.path.append("x")
        #expect(shown(app).contains("root's String x"), "\(shown(app))")
    }

    @Test("A popped screen's registration answers nothing, as SwiftUI's does")
    func poppedScreensRegistrationIsGone() {
        // navident.out, case 3C: with `String` registered on the Int screen
        // alone, a string pushed from the root once that screen has gone shows
        // no destination. Registrations used to be kept for the stack's life.
        let model = PathModel()
        let app = TestApp(width: 60, height: 6) { Strings(model: model, onRoot: false) }
        model.path.append(1)
        _ = app.screen
        model.path.append("x")
        #expect(shown(app).contains("int 1's String x"), "\(shown(app))")

        model.path.removeLast(2)
        _ = app.screen
        model.path.append("y")
        #expect(!shown(app).contains("String y"), "a popped screen's destination answered:\n\(shown(app))")
    }
}
