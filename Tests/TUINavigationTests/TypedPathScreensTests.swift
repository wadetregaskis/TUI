//  🖥️ TUI — A Terminal UI framework for Swift
//  TypedPathScreensTests.swift
//
//  A stack bound to a typed path still shows the screens that are not values
//  of its element type — a `navigationDestination(isPresented:)`'s, a
//  view-destination link's — keeping them out of the binding, as SwiftUI does.
//  Written into the binding, they were dropped: the screen never came up, and
//  the flag that asked for it went straight back to false.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUINavigation
import TUITesting

/// A stack over `[Int]`, with a flag-driven screen, a view-destination link
/// and a value link.
private struct TypedStack: View {
    @State private var path: [Int] = []
    @State private var shown = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Text(verbatim: "path=\(path) shown=\(shown)")
                Button("Show") { shown = true }
                NavigationLink("Detail") { DetailScreen(path: $path) }
                Button("Push 7") { path.append(7) }
            }
            .navigationDestination(isPresented: $shown) {
                VStack {
                    Text(verbatim: "PRESENTED")
                    Button("Append 9") { path.append(9) }
                }
            }
            .navigationDestination(for: Int.self) { value in
                VStack {
                    Text(verbatim: "VALUE \(value)")
                    NavigationLink("Over") { DetailScreen(path: $path) }
                }
            }
        }
    }
}

/// A view destination that pushes a value over itself and can empty the path.
private struct DetailScreen: View {
    @Binding var path: [Int]

    var body: some View {
        VStack {
            Text(verbatim: "DETAIL path=\(path)")
            Button("Deeper") { path.append(3) }
            Button("Clear") { path.removeAll() }
        }
    }
}

@MainActor
@Suite("A typed path's stack shows the screens its binding cannot hold")
struct TypedPathScreensTests {
    @Test("navigationDestination(isPresented:) pushes its screen, and Escape clears the flag")
    func presentedOverTypedPath() throws {
        let app = TestApp(width: 50, height: 12) { TypedStack() }
        try app.click("Show")
        #expect(app.screen.contains("PRESENTED"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("path=[] shown=false"), "\(app.screen)")
    }

    @Test("A view-destination link pushes its screen, which the binding never holds")
    func viewDestinationOverTypedPath() throws {
        let app = TestApp(width: 50, height: 12) { TypedStack() }
        try app.click("Detail")
        #expect(app.screen.contains("DETAIL path=[]"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("path=[] shown=false"), "\(app.screen)")
    }

    /// SwiftUI's, measured (`Tools/SwiftUIProbes/Navigation path and view
    /// destinations/navpath.out`, cases D to H): a value the app appends takes
    /// the place of the screens kept over the values it already held, and a
    /// flag-driven one among them has its flag set back to false.
    @Test("A value the app appends replaces the screens kept on top")
    func appendedValueReplacesTheKeptScreens() throws {
        let app = TestApp(width: 50, height: 12) { TypedStack() }
        try app.click("Detail")
        try app.click("Deeper")
        #expect(app.screen.contains("VALUE 3"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("path=[] shown=false"), "the view destination was kept under it: \(app.screen)")

        try app.click("Show")
        #expect(app.screen.contains("PRESENTED"), "\(app.screen)")
        try app.click("Append 9")
        #expect(app.screen.contains("VALUE 9"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("path=[] shown=false"), "\(app.screen)")
    }

    @Test("Taking a value off the binding pops the screens pushed over it")
    func clearingTheBindingPopsWhatWasPushedOverIt() throws {
        let app = TestApp(width: 50, height: 12) { TypedStack() }
        try app.click("Push 7")
        try app.click("Over")
        #expect(app.screen.contains("DETAIL path=[7]"), "\(app.screen)")
        try app.click("Clear")
        #expect(app.screen.contains("path=[] shown=false"), "\(app.screen)")
        // Pushed again, the value comes back alone: the screen that was over
        // it does not come back with it.
        try app.click("Push 7")
        #expect(app.screen.contains("VALUE 7"), "\(app.screen)")
        #expect(!app.screen.contains("DETAIL"), "\(app.screen)")
    }

    @Test("The merge keeps a screen while the values beneath it are unchanged and none follow, and drops it with them")
    func merging() {
        let token = AnyHashable("screen")
        let keeps: (AnyHashable) -> Bool = { $0.base is Int }
        let shadow: [AnyHashable] = [1, token]
        #expect(NavigationStack<EmptyView>.merging(shadow, over: [1], keeps: keeps) == [1, token])
        // An appended value replaces the screen kept over the last value.
        #expect(NavigationStack<EmptyView>.merging(shadow, over: [1, 2], keeps: keeps) == [1, 2])
        // A screen kept under a value that is still there stays.
        #expect(NavigationStack<EmptyView>.merging([1, token, 2], over: [1, 2, 3], keeps: keeps) == [1, token, 2, 3])
        #expect(NavigationStack<EmptyView>.merging(shadow, over: [], keeps: keeps).isEmpty)
        #expect(NavigationStack<EmptyView>.merging(shadow, over: [5], keeps: keeps) == [5])
        #expect(NavigationStack<EmptyView>.merging([], over: [4], keeps: keeps) == [4])
    }
}
