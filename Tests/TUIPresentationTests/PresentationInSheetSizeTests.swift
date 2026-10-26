//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationInSheetSizeTests.swift
//
//  A presentation attached at the root of a sheet's content — an alert, a
//  popover, another sheet — is sized as it would be over a page: the sheet's
//  detent, its proposed width and its corners are the sheet's box's, not
//  every box drawn from inside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A presentation from a sheet's root is sized as over a page", .rendersEnglishUI)
struct PresentationInSheetSizeTests {
    private static let width = 80
    private static let height = 30

    /// A frame of `view` drawn through the input chain, for a terminal of the
    /// size the presentations are sized against.
    private func frame(_ view: @autoclosure () -> some View) -> FrameBuffer {
        let harness = InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.terminalHeight = Self.height
            environment.overlayContentHeight = Self.height
        }
        harness.frame(view())
        return harness.frame(view())
    }

    /// The first layer at `level` anywhere in `buffer`'s overlays, nested ones
    /// included: what a presentation from inside a sheet floats rides up in
    /// the sheet's own layer.
    private func layer(_ level: OverlayLevel, in buffer: FrameBuffer) -> FrameBuffer? {
        for overlay in buffer.overlays {
            if overlay.level == level { return overlay.content }
            if let nested = layer(level, in: overlay.content) { return nested }
        }
        return nil
    }

    private func alert(over content: some View) -> some View {
        content.alert("Delete?", isPresented: .constant(true)) {
            Button("Delete", role: .destructive) {}
        } message: {
            Text("It cannot be undone.")
        }
    }

    /// The alert's size over a plain page.
    private var alertOverAPage: (width: Int, height: Int)? {
        layer(.alert, in: frame(alert(over: Text("page")))).map { ($0.width, $0.height) }
    }

    @Test("An alert at a detented sheet's root is as tall as over a page, not as the sheet")
    func alertInDetentedSheet() throws {
        let expected = try #require(alertOverAPage)
        let buffer = frame(
            Text("page").sheet(isPresented: .constant(true)) {
                alert(over: Text("draft")).presentationDetents([.height(20)])
            })
        let inSheet = try #require(layer(.alert, in: buffer))
        #expect(inSheet.height == expected.height, "the alert took the sheet's detent: \(inSheet.height) rows")
        #expect(inSheet.width == expected.width)
    }

    @Test("An alert at a page-sized sheet's root is as wide as over a page, not as the sheet")
    func alertInSizedSheet() throws {
        let expected = try #require(alertOverAPage)
        let buffer = frame(
            Text("page").sheet(isPresented: .constant(true)) {
                alert(over: Text("draft")).presentationSizing(.page)
            })
        let inSheet = try #require(layer(.alert, in: buffer))
        #expect(inSheet.width == expected.width, "the alert took the sheet's width: \(inSheet.width) columns")
        #expect(inSheet.height == expected.height, "the alert took the sheet's height: \(inSheet.height) rows")
    }

    @Test("A sheet with no detent presented from a detented sheet's root is its content's height")
    func sheetInDetentedSheet() throws {
        let alone = try #require(
            layer(
                .modal,
                in: frame(
                    Text("page").sheet(isPresented: .constant(true)) {
                        Dialog(title: "Inner") { Text("x") }
                    })))
        let buffer = frame(
            Text("page").sheet(isPresented: .constant(true)) {
                Text("draft")
                    .sheet(isPresented: .constant(true)) { Dialog(title: "Inner") { Text("x") } }
                    .presentationDetents([.height(20)])
            })
        let outer = try #require(layer(.modal, in: buffer))
        let inner = try #require(layer(.modal, in: outer))
        #expect(inner.height == alone.height, "the inner sheet took the outer's detent: \(inner.height) rows")
    }
}
