//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeStyleTests.swift
//
//  The window's top and bottom bars are framed by one view in one style, and
//  they are looked at together. So the thing worth pinning is the RELATION:
//  same rule, mirrored, and the same number of rows reserved as drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A page with a top bar of a title and a version, and a bottom bar of hints,
/// in one chrome style, under a horizontal gutter of its own.
private struct StyledBarsApp: App {
    var style: ChromeStyle = .bordered
    var gutter = 0

    init() {}

    init(style: ChromeStyle, gutter: Int = 0) {
        self.style = style
        self.gutter = gutter
    }

    var body: some Scene {
        WindowGroup {
            Text("page")
                .padding(.horizontal, gutter)
                .toolbar {
                    ToolbarItem(placement: .navigation) { Text("Left") }
                    ToolbarItem(placement: .primaryAction) { Text("v1.0.0") }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
        .chromeStyle(style)
    }
}

@MainActor
@Suite("Chrome style")
struct ChromeStyleTests {

    private func top(_ style: ChromeStyle, rows: Int = 1, width: Int = 40) -> FrameBuffer {
        let content = FrameBuffer(lines: (0..<rows).map { "Header \($0)" })
        return renderToBuffer(
            _ChromeBarFrame(contentBuffer: content, style: style),
            context: makeRenderContext(width: width, height: 10))
    }

    private func bottom(_ style: ChromeStyle, rows: Int = 1, width: Int = 40) -> FrameBuffer {
        let content = FrameBuffer(lines: (0..<rows).map { "Footer \($0)" })
        return renderToBuffer(
            _ChromeBarFrame(contentBuffer: content, style: style, ruleAbove: true),
            context: makeRenderContext(width: width, height: 10))
    }

    /// The frame's rows, escapes stripped, two frames in: one to declare the
    /// bars and seed them, one to draw them.
    private func screen(_ app: some App, width: Int = 40, height: Int = 12) -> [String] {
        let headless = HeadlessApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        return headless.screen.map(\.stripped)
    }

    // MARK: - Reserved space is drawn space

    @Test("Every style draws exactly the rows it reserves, on either side of the page")
    func heightsMatchWhatIsDrawn() {
        // The layout takes these heights from the page BEFORE either bar
        // renders, so a style that reserved one number and drew another would
        // overlap the content or leave a gap — and only on the styles nobody
        // ran.
        for style in ChromeStyle.allCases {
            for rows in 1...3 {
                #expect(
                    top(style, rows: rows).height == style.barHeight(contentRows: rows),
                    "\(style) top bar with \(rows) content rows")
                #expect(
                    bottom(style, rows: rows).height == style.barHeight(contentRows: rows),
                    "\(style) bottom bar with \(rows) content rows")
            }
        }
    }

    // MARK: - The two bars mirror each other

    @Test("The rule is one rule, drawn on the page-facing side of each bar")
    func theRuleMirrors() {
        // The whole reason `ChromeStyle` is one type for both bars. The top
        // bar's rule is its LAST row and the bottom bar's is its FIRST, and they
        // are the same string — which is what makes a header and a footer read
        // as one frame rather than two unrelated bars.
        let head = top(.rule)
        let foot = bottom(.rule)
        #expect(head.lines.last == foot.lines.first)
        #expect(head.lines.last?.stripped.allSatisfy { $0 == "─" } == true)
    }

    @Test("Compact draws no chrome at all")
    func compactIsBare() {
        let head = top(.compact)
        #expect(head.height == 1)
        #expect(head.lines[0].stripped.hasPrefix("Header 0"))
        #expect(bottom(.compact).height == 1)
    }

    @Test("Bordered boxes both bars")
    func borderedBoxes() {
        for buffer in [top(.bordered), bottom(.bordered)] {
            let first = buffer.lines.first?.stripped ?? ""
            let last = buffer.lines.last?.stripped ?? ""
            #expect(first.hasPrefix("╭") && first.hasSuffix("╮"), "\(first)")
            #expect(last.hasPrefix("╰") && last.hasSuffix("╯"), "\(last)")
            #expect(buffer.lines.allSatisfy { $0.strippedLength == 40 })
        }
    }

    @Test("Both bars default to the box")
    func theDefaultIsBordered() {
        // The default is a property of the app's look, and the two bars have
        // separate fields — so it is exactly the kind of thing that drifts apart
        // unnoticed (a boxed header over a ruled footer looks like a bug).
        let chrome = WindowChromeState()
        #expect(chrome.topStyle == .bordered)
        #expect(chrome.bottomStyle == .bordered)
        #expect(StatusBar(items: []).style == .bordered)
    }

    @Test("A bar lays its items out inside its walls, with a column of air each side")
    func barContentIsNotClippedByTheWall() {
        // Two halves that have to agree about one number, and used not to: the
        // width the items lay out at, and the width the frame boxes what comes
        // back at. Laying out at the full width and boxing afterwards fed the
        // last cells of every header to the right wall — on the Example,
        // "TUIkit v0.6" for "TUIkit v0.6.0". So this looks at TRAILING text,
        // which is where it shows.
        for style in ChromeStyle.allCases {
            let rows = screen(StyledBarsApp(style: style))
            let row = rows[style == .bordered ? 1 : 0]
            #expect(row.contains("v1.0.0"), "\(style) clipped the trailing text: \(row)")
            #expect(rows.allSatisfy { $0.count <= 40 }, "\(style)")
            if style == .bordered {
                #expect(row.hasPrefix("\u{2502} Left"), "\(row)")
                #expect(row.hasSuffix("v1.0.0 \u{2502}"), "\(row)")
            }
        }
    }

    /// The bars are drawn across the terminal by the window, whatever the page
    /// does with its own width — the Example's one-column gutter once put two
    /// columns of air on the right of every header and one on the left.
    @Test("A page's own padding does not move the bars' items")
    func barsIgnorePaddingOnThePage() {
        for gutter in [0, 1, 3] {
            let row = screen(StyledBarsApp(style: .bordered, gutter: gutter))[1]
            #expect(row.hasPrefix("\u{2502} Left"), "gutter \(gutter): \(row)")
            #expect(row.hasSuffix("v1.0.0 \u{2502}"), "gutter \(gutter): \(row)")
        }
    }

    @Test("A boxed bar shifts its content's click targets inside the wall")
    func borderedBarShiftsRegions() {
        // A bar can hold a Button; boxing it moves those cells right one and
        // down one, and a region left where it was would take clicks meant for
        // the border.
        var content = FrameBuffer(lines: ["Header"])
        content.hitTestRegions = [
            HitTestRegion(offsetX: 0, offsetY: 0, width: 6, height: 1, handlerID: HitTestRegion.HandlerID(1))
        ]
        let ruled = renderToBuffer(
            _ChromeBarFrame(contentBuffer: content, style: .rule),
            context: makeRenderContext(width: 40, height: 10))
        let boxed = renderToBuffer(
            _ChromeBarFrame(contentBuffer: content, style: .bordered),
            context: makeRenderContext(width: 40, height: 10))
        let ruledBelow = renderToBuffer(
            _ChromeBarFrame(contentBuffer: content, style: .rule, ruleAbove: true),
            context: makeRenderContext(width: 40, height: 10))
        #expect(ruled.hitTestRegions.first?.offsetX == 0)
        #expect(ruled.hitTestRegions.first?.offsetY == 0)
        #expect(boxed.hitTestRegions.first?.offsetX == 1)
        #expect(boxed.hitTestRegions.first?.offsetY == 1)
        #expect(ruledBelow.hitTestRegions.first?.offsetY == 1, "a rule above pushes the content down")
    }

    // MARK: - The scene modifiers

    @Test("One call sets both bars")
    func oneCallSetsBoth() {
        let scene = WindowGroup { Text("x") }.chromeStyle(.bordered)
        let resolved = scene.sceneConfiguration
        #expect(resolved.topBarStyle == .bordered)
        #expect(resolved.bottomBarStyle == .bordered)
    }

    @Test("The two-argument spelling sets them apart")
    func twoArgumentsDiffer() {
        let scene = WindowGroup { Text("x") }
            .chromeStyle(appHeader: .compact, statusBar: .bordered)
        let resolved = scene.sceneConfiguration
        #expect(resolved.topBarStyle == .compact)
        #expect(resolved.bottomBarStyle == .bordered)
    }

    @Test("Innermost wins, per bar")
    func innermostWinsPerBar() {
        // An inner call that only names one bar must not shadow an outer call
        // for the other — the two are resolved independently, which is what
        // lets `.chromeStyle(.rule)` act as a base with one bar overridden.
        let scene = WindowGroup { Text("x") }
            .chromeStyle(appHeader: .compact, statusBar: .compact)
            .chromeStyle(.bordered)
        let resolved = scene.sceneConfiguration
        #expect(resolved.topBarStyle == .compact, "the inner call is closer to the content")
        #expect(resolved.bottomBarStyle == .compact)
    }

    @Test("It composes with palette, appearance and mouse support in either order")
    func composesWithTheOtherSceneModifiers() {
        let palette = SystemPalette(.amber)
        let appearance = Appearance(id: Appearance.ID(rawValue: "test"), borderStyle: .doubleLine)

        let chromeOutermost = WindowGroup { Text("x") }
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)
            .chromeStyle(.bordered)
        let chromeInnermost = WindowGroup { Text("x") }
            .chromeStyle(.bordered)
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)

        for scene in [AnySceneProbe(chromeOutermost), AnySceneProbe(chromeInnermost)] {
            #expect(scene.chrome.appHeader == .bordered)
            #expect(scene.palette?.id == palette.id)
            #expect(scene.appearance?.id == appearance.id)
            #expect(scene.mouse != nil)
        }
    }
}

/// Reads every root-level scene override off one scene, so the composition test
/// asserts on all of them without repeating four casts per case.
@MainActor
private struct AnySceneProbe {
    let chrome: (appHeader: ChromeStyle?, statusBar: ChromeStyle?)
    let palette: (any Palette)?
    let appearance: Appearance?
    let mouse: MouseSupport?

    init(_ scene: some Scene) {
        let configuration = scene.sceneConfiguration
        chrome = (configuration.topBarStyle, configuration.bottomBarStyle)
        palette = configuration.palette
        appearance = configuration.appearance
        mouse = configuration.mouseSupport
    }
}
