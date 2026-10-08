//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeSnapshotTests.swift
//
//  Golden snapshots of WHOLE frames with chrome on them — a top bar, a bottom
//  bar holding the line of key hints, both, at each `ChromeStyle`, and the
//  interactions that cross between the chrome and the page: a top-bar menu's
//  drop-down, a sheet under a top bar, a drag preview below one. Taken from
//  what the frame diff last built for the terminal, not from a view's buffer,
//  because the chrome is assembled around the page by the scene's chrome host.
//
//  Recorded first as the oracle for moving the chrome into the scene (the A28
//  design study, §10 step 2, which left every one byte-identical); re-recorded
//  when the app header gave way to the top toolbar and the bars became opt-in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

// MARK: - Probe apps

/// A page with an optional top bar and an optional bottom bar of key hints with
/// an item of its own, in one chrome style.
private struct ChromeProbeApp: App {
    var style: ChromeStyle = .bordered
    var header = true
    var statusItem = true

    init() {}

    init(style: ChromeStyle, header: Bool, statusItem: Bool) {
        self.style = style
        self.header = header
        self.statusItem = statusItem
    }

    var body: some Scene {
        WindowGroup {
            page
        }
        .windowToolbarStyle(WindowToolbarStyleCase.drawing(style).style)
    }

    @ViewBuilder private var page: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            Text("First line of the page")
            Text("Second line")
        }
        .statusBarItems(statusItem ? [StatusBarItem(shortcut: "s", label: "save")] : [])
        content.toolbar {
            if header {
                ToolbarItem(placement: .navigation) { Text("Probe") }
                ToolbarItem(placement: .primaryAction) { Text("v1") }
            }
            if statusItem {
                ToolbarItem(placement: .bottomBar) { StatusBar() }
            }
        }
    }
}

/// A top bar holding a pull-down menu, over a page of text.
private struct HeaderMenuApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("Page row one")
                Text("Page row two")
                Text("Page row three")
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu("File") {
                        Button("Open") {}
                        Button("Close") {}
                    }
                }
                ToolbarItem(placement: .primaryAction) { Text("v1") }
                ToolbarItem(placement: .bottomBar) { StatusBar() }
            }
        }
        .mouseSupport(.full)
    }
}

/// A sheet presented over a page that has a top bar.
private struct HeaderSheetApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("Page under the sheet")
                .sheet(isPresented: .constant(true)) {
                    Text("Sheet body")
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) { Text("Header") }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
    }
}

/// A draggable chip below a top bar.
private struct HeaderDragApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(height: 2)
                Text("Drop zone")
            }
            .toolbar {
                ToolbarItem(placement: .navigation) { Text("Header") }
                ToolbarItem(placement: .bottomBar) { StatusBar() }
            }
        }
        .mouseSupport(.full)
    }
}

// MARK: - Tests

@MainActor
@Suite("Whole frames with chrome on them")
struct ChromeSnapshotTests {
    private static let millisecond: Int64 = 1_000_000

    /// The frame on screen as a buffer `assertSnapshot` can compare.
    private func screen(_ lines: [String]) -> FrameBuffer {
        FrameBuffer(lines: lines)
    }

    /// Where `text` starts on the screen, in cells.
    private func cell(of text: String, in screen: [String]) -> (x: Int, y: Int)? {
        for (y, line) in screen.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (String(line[..<range.lowerBound]).strippedLength, y)
            }
        }
        return nil
    }

    @Test(
        "The top bar, the bottom bar and both, in each chrome style",
        arguments: [ChromeStyle.bordered, .rule, .compact])
    func barsInEachStyle(style: ChromeStyle) {
        let name = "\(style)"
        for (header, statusBar, label) in [(true, false, "header"), (false, true, "statusbar"), (true, true, "both")] {
            let harness = RenderLoopHarness()
            harness.terminal.size = (40, 12)
            let loop = harness.loop(ChromeProbeApp(style: style, header: header, statusItem: statusBar))
            _ = loop.render()
            assertSnapshot("chrome-\(label)-\(name)", of: screen(loop.diffWriter.shownLines))
        }
    }

    @Test("A top-bar menu's drop-down hangs over the page")
    func headerMenuDropDown() throws {
        let app = HeadlessApp(HeaderMenuApp(), width: 40, height: 12)
        app.frame(atNanos: 0)
        let file = try #require(cell(of: "File", in: app.screen), "\(app.screen.map(\.stripped))")
        app.send(MouseEvent(button: .left, phase: .pressed, x: file.x, y: file.y))
        app.send(MouseEvent(button: .left, phase: .released, x: file.x, y: file.y))
        app.frame(atNanos: 10 * Self.millisecond)
        #expect(cell(of: "Open", in: app.screen) != nil, "the menu opened: \(app.screen.map(\.stripped))")
        assertSnapshot("chrome-header-menu-open", of: screen(app.screen))
    }

    @Test("A sheet over a page with a top bar")
    func sheetUnderHeader() {
        let app = HeadlessApp(HeaderSheetApp(), width: 40, height: 14)
        app.frame(atNanos: 0)
        assertSnapshot("chrome-header-sheet", of: screen(app.screen))
    }

    @Test("A drag preview below a top bar sits under the pointer")
    func dragPreviewBelowHeader() throws {
        let app = HeadlessApp(HeaderDragApp(), width: 30, height: 12)
        app.frame(atNanos: 0)
        let chip = try #require(cell(of: "CHIP", in: app.screen), "\(app.screen.map(\.stripped))")
        let zone = try #require(cell(of: "Drop zone", in: app.screen), "\(app.screen.map(\.stripped))")
        app.send(MouseEvent(button: .left, phase: .pressed, x: chip.x, y: chip.y))
        app.send(MouseEvent(button: .left, phase: .dragged, x: chip.x + 1, y: chip.y))
        app.frame(atNanos: 10 * Self.millisecond)
        app.send(MouseEvent(button: .left, phase: .dragged, x: zone.x + 3, y: zone.y))
        app.frame(atNanos: 20 * Self.millisecond)
        // Past the lift, so the preview sits where the pointer holds it.
        app.frame(atNanos: 300 * Self.millisecond)
        assertSnapshot("chrome-header-drag-preview", of: screen(app.screen))
    }
}
