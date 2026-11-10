//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationPathScreensTests.swift
//
//  A stack bound to a `NavigationPath` keeps the screens pushed with a view
//  destination — a `navigationDestination(isPresented:)`'s or `(item:)`'s, a
//  view-destination link's — out of the binding, as SwiftUI does
//  (`Tools/SwiftUIProbes/Navigation path and view destinations/navpath.out`):
//  the app's `count` stays its own values', and `codable` stays non-nil.
//  Written into the binding, they counted as values, and the token they were
//  pushed as made the path impossible to save.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUINavigation
import TUITesting

/// A stack over a `NavigationPath`, with a flag-driven screen on the root, a
/// view-destination link, and a value screen with its own flag-driven screen.
private struct PathStack: View {
    @State private var path = NavigationPath()
    @State private var shown = false
    @State private var inner = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Text(verbatim: "count=\(path.count) codable=\(path.codable != nil) shown=\(shown) inner=\(inner)")
                Button("Show") { shown = true }
                NavigationLink("Detail") { Text(verbatim: "DETAIL count=\(path.count)") }
                Button("Push 7") { path.append(7) }
            }
            .navigationDestination(isPresented: $shown) {
                VStack {
                    Text(verbatim: "PRESENTED count=\(path.count) codable=\(path.codable != nil)")
                    NavigationLink("Deeper", value: 5)
                    Button("Append 9") { path.append(9) }
                }
            }
            .navigationDestination(for: Int.self) { value in
                VStack {
                    Text(verbatim: "VALUE \(value) inner=\(inner) shown=\(shown)")
                    Button("Inner") { inner = true }
                    Button("Hide") { shown = false }
                }
                .navigationDestination(isPresented: $inner) {
                    VStack {
                        Text(verbatim: "INNER count=\(path.count)")
                        Button("Pop value") { path.removeLast() }
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("A NavigationPath binding holds only the app's values")
struct NavigationPathScreensTests {
    @Test("navigationDestination(isPresented:) shows its screen, and the path stays empty and codable")
    func presentedLeavesThePathAlone() throws {
        let app = TestApp(width: 60, height: 12) { PathStack() }
        try app.click("Show")
        #expect(app.screen.contains("PRESENTED count=0 codable=true"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("count=0 codable=true shown=false"), "\(app.screen)")
    }

    @Test("A view-destination link shows its screen, which the path never counts")
    func viewDestinationLeavesThePathAlone() throws {
        let app = TestApp(width: 60, height: 12) { PathStack() }
        try app.click("Detail")
        #expect(app.screen.contains("DETAIL count=0"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("count=0 codable=true shown=false"), "\(app.screen)")
    }

    @Test("Taking a value off the path takes the screen pushed over it, and clears its flag")
    func poppingTheValuePopsTheScreenOverIt() throws {
        let app = TestApp(width: 60, height: 12) { PathStack() }
        try app.click("Push 7")
        try app.click("Inner")
        #expect(app.screen.contains("INNER count=1"), "\(app.screen)")
        try app.click("Pop value")
        #expect(app.screen.contains("count=0 codable=true shown=false inner=false"), "\(app.screen)")
        // Pushed again, the value comes back alone: the screen that was over it
        // went with it, and stays gone.
        try app.click("Push 7")
        #expect(app.screen.contains("VALUE 7 inner=false"), "\(app.screen)")
        #expect(!app.screen.contains("INNER"), "\(app.screen)")
    }

    @Test("A value the stack pushes over the screen goes into the path, and leaves with the screen")
    func valuePushedOverTheScreenLeavesWithIt() throws {
        let app = TestApp(width: 60, height: 12) { PathStack() }
        try app.click("Show")
        try app.click("Deeper")
        #expect(app.screen.contains("VALUE 5 inner=false shown=true"), "\(app.screen)")
        // Clearing the flag takes the screen off, and what was pushed over it:
        // left, it would strand the user on a screen reached through one gone.
        try app.click("Hide")
        #expect(app.screen.contains("count=0 codable=true shown=false"), "\(app.screen)")
    }

    /// SwiftUI's, measured (`Tools/SwiftUIProbes/Navigation path and view
    /// destinations/navpath.out`, cases D to H).
    @Test("A value the app appends replaces the screen on top, and clears its flag")
    func appendedValueReplacesTheScreen() throws {
        let app = TestApp(width: 60, height: 12) { PathStack() }
        try app.click("Show")
        try app.click("Append 9")
        #expect(app.screen.contains("VALUE 9 inner=false shown=false"), "\(app.screen)")
        app.press(.escape)
        #expect(app.screen.contains("count=0 codable=true shown=false"), "\(app.screen)")
    }
}
