//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarBackgroundTests.swift
//
//  `.toolbarBackground(_:for:)` fills a window bar with a style of the page's
//  in place of the palette's surface, and `.toolbarBackgroundVisibility(_:for:)`
//  draws it with no fill at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A palette whose page and two bars are three different colours, so a row
/// says which it is filled with.
private struct ThreeGrounds: Palette {
    let id = "three-grounds"
    let name = "Three grounds"
    let background = Color.rgb(10, 10, 10)
    let statusBarBackground = Color.rgb(20, 20, 60)
    let appHeaderBackground = Color.rgb(60, 20, 20)
    let foreground = Color.rgb(230, 230, 230)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// What the probe page states about its bars, reachable from an `App`.
private final class BarFills: @unchecked Sendable {
    static let shared = BarFills()
    var top: Color?
    var bottom: Color?
    var innerTop: Color?
    var gradientTop = false
    var bottomShown: Visibility = .automatic
}

/// A top bar and a bottom bar, each filled as `BarFills` says.
private struct FillsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            page
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("TOP-ITEM") }
                    ToolbarItem(placement: .bottomBar) { Text("BOTTOM-ITEM") }
                }
                .toolbarBackgroundVisibility(BarFills.shared.bottomShown, for: .bottomBar)
        }
        .palette(ThreeGrounds())
        .windowToolbarStyle(.unifiedCompact)
    }

    /// The page, with each statement only when the probe makes it.
    @ViewBuilder private var page: some View {
        let fills = BarFills.shared
        let top = fills.top ?? Color.palette.appHeaderBackground
        if fills.gradientTop {
            Text("PAGE").toolbarBackground(
                LinearGradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)], startPoint: .leading, endPoint: .trailing),
                for: .windowToolbar)
        } else if let inner = fills.innerTop {
            Text("PAGE").toolbarBackground(inner).toolbarBackground(top, for: .windowToolbar)
        } else {
            Text("PAGE")
                .toolbarBackground(top, for: .windowToolbar)
                .toolbarBackground(fills.bottom ?? Color.palette.statusBarBackground, for: .bottomBar)
        }
    }
}

@MainActor
@Suite("Toolbar background", .serialized)
struct ToolbarBackgroundTests {

    private func reset() {
        BarFills.shared.top = nil
        BarFills.shared.bottom = nil
        BarFills.shared.innerTop = nil
        BarFills.shared.gradientTop = false
        BarFills.shared.bottomShown = .automatic
    }

    /// The screen, two frames in — one to declare the bars, one to draw them —
    /// as raw lines.
    private func screen() -> [String] {
        let app = HeadlessApp(FillsApp(), width: 30, height: 6)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen
    }

    private func row(_ rows: [String], containing marker: String) -> String {
        rows.first { $0.stripped.contains(marker) } ?? ""
    }

    @Test("A style stated for the top bar fills it, and only it")
    func fillsTheTopBar() {
        reset()
        defer { reset() }
        BarFills.shared.top = .rgb(0, 200, 0)
        let rows = screen()
        let green = ANSIRenderer.backgroundCode(for: .rgb(0, 200, 0))
        #expect(row(rows, containing: "TOP-ITEM").contains(green), "\(rows)")
        #expect(!row(rows, containing: "BOTTOM-ITEM").contains(green), "\(rows)")
        #expect(row(rows, containing: "BOTTOM-ITEM").contains(ANSIRenderer.backgroundCode(for: .rgb(20, 20, 60))))
    }

    @Test("A style stated for the bottom bar fills it in place of the palette's surface")
    func fillsTheBottomBar() {
        reset()
        defer { reset() }
        BarFills.shared.bottom = .rgb(200, 200, 0)
        let rows = screen()
        let bottom = row(rows, containing: "BOTTOM-ITEM")
        #expect(bottom.contains(ANSIRenderer.backgroundCode(for: .rgb(200, 200, 0))), "\(rows)")
        #expect(!bottom.contains(ANSIRenderer.backgroundCode(for: .rgb(20, 20, 60))), "\(rows)")
    }

    @Test("The statement closest to the content wins")
    func innermostWins() {
        reset()
        defer { reset() }
        BarFills.shared.top = .rgb(0, 200, 0)
        BarFills.shared.innerTop = .rgb(0, 0, 200)
        let top = row(screen(), containing: "TOP-ITEM")
        #expect(top.contains(ANSIRenderer.backgroundCode(for: .rgb(0, 0, 200))), "\(top)")
        #expect(!top.contains(ANSIRenderer.backgroundCode(for: .rgb(0, 200, 0))), "\(top)")
    }

    @Test("A hidden fill draws the bar on the page's own background")
    func hiddenFillShowsThePage() {
        reset()
        defer { reset() }
        BarFills.shared.bottomShown = .hidden
        let rows = screen()
        let bottom = row(rows, containing: "BOTTOM-ITEM")
        #expect(!bottom.contains(ANSIRenderer.backgroundCode(for: .rgb(20, 20, 60))), "\(rows)")
        #expect(row(rows, containing: "TOP-ITEM").contains(ANSIRenderer.backgroundCode(for: .rgb(60, 20, 20))))
    }

    @Test("A gradient is laid across the bar")
    func gradientFill() {
        reset()
        defer { reset() }
        BarFills.shared.gradientTop = true
        let top = row(screen(), containing: "TOP-ITEM")
        #expect(!top.contains(ANSIRenderer.backgroundCode(for: .rgb(60, 20, 20))), "\(top)")
        // A ramp from red to blue: many fills along the row, not one.
        let fills = Set(top.matches(of: /48;(2;\d+;\d+;\d+|5;\d+)/).map { String($0.output.0) })
        #expect(fills.count >= 4, "\(fills)")
    }
}
