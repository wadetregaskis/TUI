//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationBackgroundTests.swift
//
//  `presentationBackground`: it fills the whole presentation — a sheet's box,
//  a cover's whole area, a popover's panel — and is found through the other
//  presentation traits, in either order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport

@MainActor
@Suite("Presentation backgrounds", .rendersEnglishUI)
struct PresentationBackgroundTests {
    /// The composited screen, with its escape codes: the fill is a colour.
    private func screen(_ view: some View) -> [String] {
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 40, maxHeight: 12, palette: context.environment.palette)
            .lines
    }

    private func sheet(_ content: some View) -> some View {
        Text("page").sheet(isPresented: .constant(true)) { content }
    }

    @Test("A sheet's background fills behind its content and changes no text")
    func sheetBackground() {
        let plain = screen(sheet(Dialog(title: "Edit") { Text("body") }))
        let filled = screen(sheet(Dialog(title: "Edit") { Text("body") }.presentationBackground(Color.blue)))
        #expect(plain.map(\.stripped) == filled.map(\.stripped))
        #expect(plain != filled)
    }

    @Test("A cover's background fills the whole content area, far from the content")
    func coverBackground() {
        let cover = { (filled: Bool) in
            self.screen(
                Text("page").fullScreenCover(isPresented: .constant(true)) {
                    if filled {
                        Text("loading").presentationBackground(Color.blue)
                    } else {
                        Text("loading")
                    }
                })
        }
        #expect(cover(false).last != cover(true).last, "the bottom row, nowhere near the text, is filled")
    }

    @Test("A popover's background replaces the page's in its panel")
    func popoverBackground() {
        let popover = { (filled: Bool) in
            self.screen(
                Text("page").popover(isPresented: .constant(true)) {
                    if filled {
                        Text("tip").presentationBackground(Color.blue)
                    } else {
                        Text("tip")
                    }
                })
        }
        #expect(popover(false).map(\.stripped) == popover(true).map(\.stripped))
        #expect(popover(false) != popover(true))
    }

    @Test("A background view is drawn behind a cover, placed by its alignment")
    func coverBackgroundView() {
        // A cover is the terminal's width and the content area's height, so
        // both are this screen's.
        var context = RenderContext(availableWidth: 40, availableHeight: 12, tuiContext: TUIContext())
            .isolatingRenderCache()
        context.environment.terminalWidth = 40
        context.environment.terminalHeight = 12
        context.environment.overlayContentHeight = 12
        let cover = { (alignment: Alignment?) in
            renderToBuffer(
                Text("page").fullScreenCover(isPresented: .constant(true)) {
                    if let alignment {
                        Text("loading").presentationBackground(alignment: alignment) {
                            Color.blue.frame(width: 4, height: 1)
                        }
                    } else {
                        Text("loading")
                    }
                },
                context: context
            )
            .compositingOverlays(maxWidth: 40, maxHeight: 12, palette: context.environment.palette)
            .lines
        }
        let plain = cover(nil)
        let trailing = cover(.bottomTrailing)
        let leading = cover(.bottomLeading)
        // A background's glyphs show only where the cover draws no cell, and it
        // draws every one (`background(alignment:content:)`), so the view shows
        // as its colour: an SGR code the plain cover's bottom row lacks. The
        // text before a row's first ESC[ is not a code, so it is dropped, not
        // kept as one (a row that starts with text would otherwise add its
        // leading text to the set, and a set difference could be non-empty
        // with no code in it).
        func codes(_ line: String?) -> Set<Substring> {
            Set(
                (line ?? "").split(separator: "\u{1B}[", omittingEmptySubsequences: false)
                    .dropFirst()
                    .map { $0.prefix { $0 != "m" } })
        }
        let fill = codes(trailing.last).subtracting(codes(plain.last))
        #expect(plain.map(\.stripped) == trailing.map(\.stripped), "the text is unchanged")
        #expect(!fill.isEmpty, "the bottom row is filled: \(trailing.last ?? "")")
        #expect(trailing.dropLast().allSatisfy { codes($0).isDisjoint(with: fill) }, "and no row above it")
        #expect(trailing.last != leading.last, "where the alignment puts it")
    }

    @Test("The background is found through a detent around it, and a detent through it")
    func throughOtherTraits() {
        let outer = screen(
            sheet(
                Dialog(title: "Edit") { Text("body") }
                    .presentationBackground(Color.blue)
                    .presentationDetents([.height(8)])))
        let inner = screen(
            sheet(
                Dialog(title: "Edit") { Text("body") }
                    .presentationDetents([.height(8)])
                    .presentationBackground(Color.blue)))
        let none = screen(sheet(Dialog(title: "Edit") { Text("body") }.presentationDetents([.height(8)])))
        #expect(outer == inner, "the order of the two traits does not matter")
        #expect(outer != none, "and the background is applied either way")
        #expect(outer.map(\.stripped) == none.map(\.stripped), "with the detent still deciding the height")
    }
}
