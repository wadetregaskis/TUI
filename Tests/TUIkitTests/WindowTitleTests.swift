//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowTitleTests.swift
//
//  The window's title — what the top bar's title slot shows — is the
//  outermost `.navigationTitle` among the views drawn: the page's own over a
//  navigation stack's inside it, a pushed screen's when nothing outside the
//  stack has one, and never a sheet's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

/// A titled page under a sheet whose content is titled too.
private struct SheetTitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .navigationTitle("PAGE-TITLE")
                .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
                .sheet(isPresented: .constant(true)) {
                    Text("SHEET").navigationTitle("SHEET-TITLE").navigationSubtitle("SHEET-SUB")
                }
        }
    }
}

/// A titled page that holds a navigation stack with a titled root — the
/// Example's Navigation page, in small.
private struct NestedStackApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("INTRO")
                NavigationStack {
                    Text("ROOT").navigationTitle("ROOT-TITLE")
                }
            }
            .navigationTitle("PAGE-TITLE")
            .navigationSubtitle("PAGE-SUB")
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A navigation stack at the window's root, a screen pushed or not.
private struct RootStackApp: App {
    nonisolated(unsafe) static var path: [Int] = []

    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant(Self.path)) {
                Text("ROOT")
                    .navigationTitle("ROOT-TITLE")
                    .navigationDestination(for: Int.self) { Text("DETAIL \($0)").navigationTitle("DETAIL-TITLE") }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A page whose subtitle is its own, holding a stack whose root has a title
/// and a subtitle of its own — the page itself has no title.
private struct SubtitledPageApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                NavigationStack {
                    Text("ROOT").navigationTitle("PLANETS").navigationSubtitle("NINE-PLANETS")
                }
            }
            .navigationSubtitle("DEMO")
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A page whose title is on a view inside it and whose subtitle is on the
/// page.
private struct SubtitleAroundTheTitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("HEADER").navigationTitle("NOTES")
                Text("BODY")
            }
            .navigationSubtitle("THREE-NOTES")
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A titled view beside one with a subtitle: SwiftUI's `VStack { header;
/// list }` with the count on the list.
private struct SiblingSubtitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("HEADER").navigationTitle("NOTES")
                Text("LIST").navigationSubtitle("THREE-NOTES")
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A titled view inside two views with subtitles, one round the other.
private struct NestedSubtitlesApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                VStack {
                    Text("HEADER").navigationTitle("NOTES")
                }
                .navigationSubtitle("INNER-SUB")
            }
            .navigationSubtitle("OUTER-SUB")
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A titled view with a subtitle of its own beside a titled view with none —
/// a detail and its inspector.
private struct SiblingTitledSubtitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            HStack {
                Text("DETAIL").navigationTitle("INBOX").navigationSubtitle("UNREAD")
                Text("INSPECTOR").navigationTitle("INFO")
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A subtitle round a sibling's title — a sidebar whose subtitle is on the
/// view round its titled list — beside a titled view with none.
private struct SiblingRoundSubtitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            HStack {
                VStack { Text("SIDEBAR").navigationTitle("MAIL") }.navigationSubtitle("ACCOUNTS")
                Text("DETAIL").navigationTitle("INFO")
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A subtitle round the title, and a later sibling with one of its own.
private struct RoundAndBesideSubtitleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            HStack {
                VStack { Text("H").navigationTitle("NOTES") }.navigationSubtitle("THREE-NOTES")
                Text("FOOTER").navigationSubtitle("SYNCED")
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// Two titled views side by side, the second one wrapped or not.
private struct SiblingTitlesApp: App {
    var wrapped = false

    init() {}

    init(wrapped: Bool) { self.wrapped = wrapped }

    var body: some Scene {
        WindowGroup {
            HStack {
                Text("A").navigationTitle("MAIL")
                if wrapped {
                    VStack { Text("B").navigationTitle("INBOX") }
                } else {
                    Text("B").navigationTitle("INBOX")
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

/// A title and a subtitle stacked over another pair on one view, with a
/// `.padding()` between them or not.
private struct StackedTitlesApp: App {
    var padded = false

    init() {}

    init(padded: Bool) { self.padded = padded }

    var body: some Scene {
        WindowGroup {
            Group {
                if padded {
                    Text("R").navigationTitle("INNER").navigationSubtitle("INNER-SUB").padding()
                        .navigationTitle("OUTER").navigationSubtitle("OUTER-SUB")
                } else {
                    Text("R").navigationTitle("INNER").navigationSubtitle("INNER-SUB")
                        .navigationTitle("OUTER").navigationSubtitle("OUTER-SUB")
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

@MainActor
@Suite("The window's title", .serialized)
struct WindowTitleTests {

    /// The top bar's rows, escapes stripped, two frames in: one to declare,
    /// one to draw. The bar is boxed, so its rows lie between the first two
    /// border rows.
    private func topBar(_ app: some App, width: Int = 60, height: Int = 16) -> [String] {
        let headless = HeadlessApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        let rows = headless.screen.map(\.stripped)
        guard rows.first?.hasPrefix("╭") == true,
            let bottom = rows.dropFirst().firstIndex(where: { $0.hasPrefix("╰") })
        else { return [] }
        return Array(rows[1..<bottom])
    }

    @Test("A sheet's title is not the window's")
    func sheetTitleIsNotTheWindows() {
        let bar = topBar(SheetTitleApp())
        #expect(bar.first?.contains("PAGE-TITLE") == true, "\(bar)")
        #expect(!bar.contains { $0.contains("SHEET-TITLE") || $0.contains("SHEET-SUB") }, "\(bar)")
    }

    @Test("A page's own title, and its subtitle, stand over a navigation stack's inside it")
    func pageTitleOverANestedStack() {
        let bar = topBar(NestedStackApp())
        #expect(bar.count == 2, "a title and a subtitle: \(bar)")
        #expect(bar.first?.contains("PAGE-TITLE") == true, "\(bar)")
        #expect(bar.last?.contains("PAGE-SUB") == true, "\(bar)")
        #expect(!bar.contains { $0.contains("ROOT-TITLE") }, "\(bar)")
    }

    @Test("The subtitle is the title's own, not an outer view's")
    func subtitleIsTheTitles() {
        let bar = topBar(SubtitledPageApp())
        #expect(bar.first?.contains("PLANETS") == true, "\(bar)")
        #expect(bar.last?.contains("NINE-PLANETS") == true, "the root's own subtitle: \(bar)")
        #expect(!bar.contains { $0.contains("DEMO") }, "not the page's, under another view's title: \(bar)")
    }

    @Test("With none of its own, the title takes the subtitle of a view round it")
    func subtitleFromAroundTheTitle() {
        let bar = topBar(SubtitleAroundTheTitleApp())
        #expect(bar.first?.contains("NOTES") == true, "\(bar)")
        #expect(bar.last?.contains("THREE-NOTES") == true, "\(bar)")
    }

    @Test("With none of its own, the title takes the subtitle of a view beside it, as the preference combines siblings")
    func subtitleFromBesideTheTitle() {
        let bar = topBar(SiblingSubtitleApp())
        #expect(bar.count == 2, "a title and a subtitle: \(bar)")
        #expect(bar.first?.contains("NOTES") == true, "\(bar)")
        #expect(bar.last?.contains("THREE-NOTES") == true, "\(bar)")
    }

    @Test("Of subtitles round the title, the outermost stands, as a title's does")
    func outermostSubtitleRoundTheTitle() {
        let bar = topBar(NestedSubtitlesApp())
        #expect(bar.last?.contains("OUTER-SUB") == true, "\(bar)")
        #expect(!bar.contains { $0.contains("INNER-SUB") }, "\(bar)")
    }

    @Test("A subtitle another titled view declared is that view's, not the window title's")
    func siblingTitlesSubtitleIsItsOwn() {
        let bar = topBar(SiblingTitledSubtitleApp())
        #expect(bar.first?.contains("INFO") == true, "the later title stands: \(bar)")
        #expect(!bar.contains { $0.contains("UNREAD") }, "the inbox's subtitle, not the inspector's: \(bar)")
    }

    @Test("A subtitle round another titled view is that view's, not the window title's")
    func subtitleRoundASiblingTitleIsItsOwn() {
        let bar = topBar(SiblingRoundSubtitleApp())
        #expect(bar.first?.contains("INFO") == true, "\(bar)")
        #expect(!bar.contains { $0.contains("ACCOUNTS") }, "the sidebar's subtitle: \(bar)")
    }

    @Test("A subtitle round the title stands over a later sibling's")
    func subtitleRoundTheTitleBeatsASiblings() {
        let bar = topBar(RoundAndBesideSubtitleApp())
        #expect(bar.first?.contains("NOTES") == true, "\(bar)")
        #expect(bar.last?.contains("THREE-NOTES") == true, "the enclosing view's: \(bar)")
        #expect(!bar.contains { $0.contains("SYNCED") }, "\(bar)")
    }

    @Test("Of two titles side by side, the same one stands however each is wrapped", arguments: [false, true])
    func siblingTitlesIgnoreWrappers(wrapped: Bool) {
        let bar = topBar(SiblingTitlesApp(wrapped: wrapped))
        #expect(bar.first?.contains("INBOX") == true, "the later one, as the preference has it: \(bar)")
        #expect(!bar.contains { $0.contains("MAIL") }, "\(bar)")
    }

    @Test("Of two titles stacked on one view the outer stands, and so does the outer subtitle", arguments: [false, true])
    func stackedTitlesOuterStands(padded: Bool) {
        let bar = topBar(StackedTitlesApp(padded: padded))
        #expect(bar.first?.contains("OUTER") == true, "the outer writer overrides its content: \(bar)")
        #expect(bar.last?.contains("OUTER-SUB") == true, "\(bar)")
        #expect(!bar.contains { $0.contains("INNER") }, "\(bar)")
    }

    @Test("A stack at the window's root titles it: its root's title, and a pushed screen's while it is shown")
    func rootStackTitlesTheWindow() {
        RootStackApp.path = []
        #expect(topBar(RootStackApp()).first?.contains("ROOT-TITLE") == true)
        RootStackApp.path = [1]
        let pushed = topBar(RootStackApp())
        #expect(pushed.first?.contains("DETAIL-TITLE") == true, "\(pushed)")
        #expect(!pushed.contains { $0.contains("ROOT-TITLE") }, "the covered root is not drawn: \(pushed)")
        RootStackApp.path = []
    }
}
