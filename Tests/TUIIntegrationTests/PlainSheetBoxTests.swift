//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainSheetBoxTests.swift
//
//  A sheet of plain content — a stack, not a `Dialog` or a `Panel` — is a box
//  as SwiftUI's sheet is: opaque over its whole extent, and as tall as its
//  detent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A sheet of plain content")
struct PlainSheetBoxTests {
    private static let width = 40
    private static let height = 20

    private func harness() -> InputChainHarness {
        InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
    }

    /// A page of `x`s under a sheet, so anything showing through shows.
    private func page(_ sheet: some View) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.height, id: \.self) { _ in
                Text(verbatim: String(repeating: "x", count: Self.width))
            }
        }
        .sheet(isPresented: .constant(true)) { sheet }
    }

    /// The sheet's own layer.
    private func layer(_ harness: InputChainHarness, _ view: some View) throws -> FrameBuffer {
        try #require(harness.frame(view).overlays.first { $0.level == .modal }).content
    }

    @Test("Centred, its gaps hide the page: every row is the box's width")
    func centredIsOpaque() throws {
        let sheet = try layer(
            harness(),
            page(
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "a")
                    Text(verbatim: "longer line")
                }))
        #expect(sheet.height == 3, "\(sheet.lines.map(\.stripped))")
        for line in sheet.lines {
            #expect(line.strippedLength == sheet.width, "a row painted short: \(sheet.lines.map(\.stripped))")
        }
    }

    @Test("Detented, it is as tall as its detent")
    func detentedFillsItsDetent() throws {
        let sheet = try layer(
            harness(),
            page(
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "top")
                    Text(verbatim: "Close").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .presentationDetents([.height(9)])
                .presentationDragIndicator(.hidden)))
        #expect(sheet.height == 9, "\(sheet.lines.map(\.stripped))")
    }
}
