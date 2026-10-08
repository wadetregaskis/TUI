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

import TUIkit
@testable import TUIkitFoundation

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
