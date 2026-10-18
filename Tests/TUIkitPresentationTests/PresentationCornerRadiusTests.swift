//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationCornerRadiusTests.swift
//
//  `presentationCornerRadius`: a sheet's box takes the corners its content
//  names — square at zero, rounded above — found through the other
//  presentation traits, and only the outermost box takes them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport

@MainActor
@Suite("Presentation corner radius", .rendersEnglishUI)
struct PresentationCornerRadiusTests {
    /// The composited screen's text.
    private func screen(_ view: some View, appearance: Appearance = .rounded) -> String {
        var context = RenderContext(
            availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
        ).isolatingRenderCache()
        context.environment.appearance = appearance
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 40, maxHeight: 12, palette: context.environment.palette)
            .lines.map(\.stripped).joined(separator: "\n")
    }

    private func sheet(_ content: some View) -> some View {
        Text("page").sheet(isPresented: .constant(true)) { content }
    }

    @Test("Zero squares a rounded sheet's corners, a radius rounds a square one, nil leaves them")
    func corners() {
        let rounded = screen(sheet(Dialog(title: "Edit") { Text("body") }))
        #expect(rounded.contains("╭") && !rounded.contains("┌"))
        let squared = screen(sheet(Dialog(title: "Edit") { Text("body") }.presentationCornerRadius(0)))
        #expect(squared.contains("┌") && !squared.contains("╭"))
        let roundedAgain = screen(
            sheet(Dialog(title: "Edit") { Text("body") }.presentationCornerRadius(8)), appearance: .line)
        #expect(roundedAgain.contains("╭") && !roundedAgain.contains("┌"))
        let left = screen(sheet(Dialog(title: "Edit") { Text("body") }.presentationCornerRadius(nil)))
        #expect(left == rounded)
    }

    @Test("Found through another trait, and taken by the outermost box alone")
    func outermost() {
        let nested = screen(
            sheet(
                Dialog(title: "Edit") { Text("inner").border() }
                    .presentationCornerRadius(0)
                    .presentationDetents([.medium])))
        // The dialog's corners are square; the box inside keeps the appearance's.
        #expect(nested.contains("┌"))
        #expect(nested.contains("╭"))
    }

    @Test("A heavy box has no rounded corner to take")
    func heavy() {
        let heavy = screen(sheet(Dialog(title: "Edit") { Text("body") }.presentationCornerRadius(8)), appearance: .heavy)
        #expect(heavy.contains("┏"))
    }
}
