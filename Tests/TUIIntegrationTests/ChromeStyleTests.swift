//  🖥️ TUI — A Terminal UI framework for Swift
//  ChromeStyleTests.swift
//
//  The window's top and bottom bars are framed by one view in one style, and
//  they are looked at together. So the thing worth pinning is the RELATION:
//  same rule, mirrored, and the same number of rows reserved as drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

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
        .windowToolbarStyle(WindowToolbarStyleCase.drawing(style).style)
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
        let headless = TestApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        return headless.screen.lines
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
        #expect(chrome.style(.top) == .bordered)
        #expect(chrome.style(.bottom) == .bordered)
        #expect(StatusBar(items: []).style == .bordered)
    }

    @Test("A bar lays its items out inside its walls, with a column of air each side")
    func barContentIsNotClippedByTheWall() {
        // Two halves that have to agree about one number, and used not to: the
        // width the items lay out at, and the width the frame boxes what comes
        // back at. Laying out at the full width and boxing afterwards fed the
        // last cells of every header to the right wall — on the Example,
        // "TUI v0.6" for "TUI v0.6.0". So this looks at TRAILING text,
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

    // MARK: - The scene modifier

    @Test("Each window toolbar style draws its frame round every bar", arguments: [
        (WindowToolbarStyleCase.automatic, ChromeStyle.bordered),
        (.expanded, .bordered),
        (.unified, .rule),
        (.unifiedCompact, .compact),
    ])
    func windowToolbarStyles(style: WindowToolbarStyleCase, chrome: ChromeStyle) {
        let resolved = WindowGroup { Text("x") }.windowToolbarStyle(style.style).sceneConfiguration
        #expect(resolved.toolbarStyle == chrome)
        #expect(resolved.showsTitle == true)
    }

    @Test("The showsTitle: forms say whether the title slot shows the title")
    func showsTitle() {
        let hidden = WindowGroup { Text("x") }.windowToolbarStyle(.unified(showsTitle: false)).sceneConfiguration
        #expect(hidden.toolbarStyle == .rule)
        #expect(hidden.showsTitle == false)
        let compact = WindowGroup { Text("x") }.windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .sceneConfiguration
        #expect(compact.toolbarStyle == .compact)
        #expect(compact.showsTitle == false)
    }

    @Test("A title the style hides is not drawn, though the bar still is")
    func hiddenTitleIsNotDrawn() {
        struct TitledApp: App {
            init() {}
            var body: some Scene {
                WindowGroup {
                    Text("page")
                        .navigationTitle("TITLE")
                        .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
                }
                .windowToolbarStyle(.unified(showsTitle: false))
            }
        }
        let rows = screen(TitledApp())
        #expect(rows[0].contains("ITEM"), "\(rows)")
        #expect(!rows.contains { $0.contains("TITLE") }, "\(rows)")
    }

    @Test("Innermost wins")
    func innermostWins() {
        let scene = WindowGroup { Text("x") }
            .windowToolbarStyle(.unifiedCompact)
            .windowToolbarStyle(.expanded)
        #expect(scene.sceneConfiguration.toolbarStyle == .compact, "the inner call is closer to the content")
    }

    @Test("A style of the app's own is read as the default")
    func unknownStyleIsAutomatic() {
        struct Mine: WindowToolbarStyle {}
        let resolved = WindowGroup { Text("x") }.windowToolbarStyle(Mine()).sceneConfiguration
        #expect(resolved.toolbarStyle == .bordered)
    }

    @Test("It composes with palette, appearance and mouse support in either order")
    func composesWithTheOtherSceneModifiers() {
        let palette = SystemPalette(.amber)
        let appearance = Appearance(id: Appearance.ID(rawValue: "test"), borderStyle: .doubleLine)

        let chromeOutermost = WindowGroup { Text("x") }
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)
            .windowToolbarStyle(.unified)
        let chromeInnermost = WindowGroup { Text("x") }
            .windowToolbarStyle(.unified)
            .palette(palette)
            .appearance(appearance)
            .mouseSupport(.standard)

        for scene in [AnySceneProbe(chromeOutermost), AnySceneProbe(chromeInnermost)] {
            #expect(scene.chrome == .rule)
            #expect(scene.palette?.id == palette.id)
            #expect(scene.appearance?.id == appearance.id)
            #expect(scene.mouse != nil)
        }
    }
}

/// The window toolbar styles, as test arguments: each erased for
/// `windowToolbarStyle(_:)`'s run-time form.
enum WindowToolbarStyleCase: Sendable, CustomTestStringConvertible {
    case automatic, expanded, unified, unifiedCompact

    var style: any WindowToolbarStyle {
        switch self {
        case .automatic: .automatic
        case .expanded: .expanded
        case .unified: .unified
        case .unifiedCompact: .unifiedCompact
        }
    }

    /// The style that draws `chrome`.
    static func drawing(_ chrome: ChromeStyle) -> Self {
        switch chrome {
        case .bordered: .expanded
        case .rule: .unified
        case .compact: .unifiedCompact
        }
    }

    var testDescription: String { "\(self)" }
}

/// Reads every root-level scene override off one scene, so the composition test
/// asserts on all of them without repeating four casts per case.
@MainActor
private struct AnySceneProbe {
    let chrome: ChromeStyle?
    let palette: (any Palette)?
    let appearance: Appearance?
    let mouse: MouseSupport?

    init(_ scene: some Scene) {
        let configuration = scene.sceneConfiguration
        chrome = configuration.toolbarStyle
        palette = configuration.palette
        appearance = configuration.appearance
        mouse = configuration.mouseSupport
    }
}
