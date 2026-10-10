//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStyleVariantTests.swift
//
//  SwiftUI's macOS list styles: `.automatic` and `.bordered` a box,
//  `.inset` borderless with its rows a cell in from the edges, `.sidebar`
//  borderless with its rows' `Label` icons in the list item tint.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("List style variants")
struct ListStyleVariantTests {
    private let palette = SystemPalette.green

    private func context() -> RenderContext {
        var context = makeRenderContext(width: 20, height: 5)
        context.environment.palette = palette
        return context
    }

    private func lines<S: ListStyle>(_ style: S, tint: ListItemTint? = nil) -> [String] {
        let list = List {
            Label {
                Text("Inbox")
            } icon: {
                Text("*")
            }
            .listItemTint(tint)
        }
        .listStyle(style)
        return renderToBuffer(list, context: context()).lines
    }

    private func row(_ lines: [String]) -> String {
        lines.first { $0.stripped.contains("Inbox") } ?? ""
    }

    @Test(".automatic and .bordered draw the box the default list draws")
    func automaticAndBordered() {
        let unstyled = renderToBuffer(
            List { Label { Text("Inbox") } icon: { Text("*") } }, context: context()
        ).lines
        #expect(lines(.automatic) == unstyled)
        #expect(lines(.bordered) == unstyled)
        #expect(unstyled.first?.stripped.hasPrefix("╭") == true, "\(unstyled.map(\.stripped))")
    }

    @Test(".inset draws no border and puts the rows a cell in from each edge")
    func inset() {
        let plain = lines(.plain).map(\.stripped)
        let inset = lines(.inset).map(\.stripped)
        #expect(!inset.joined().contains("│"), "\(inset)")
        let plainRow = plain.first { $0.contains("Inbox") } ?? ""
        let insetRow = inset.first { $0.contains("Inbox") } ?? ""
        let expected: String = " " + plainRow.dropLast(2) + " "
        #expect(insetRow == expected, "'\(insetRow)' against '\(plainRow)'")
    }

    @Test(".sidebar draws no border and its rows' label icons in the accent")
    func sidebarTintsIcons() {
        let sidebar = row(lines(.sidebar))
        let accentIcon = ANSIRenderer.colorize("*", foreground: palette.accent.opaqueSpelling)
        #expect(sidebar.contains(accentIcon), "\(sidebar.debugDescription)")
        #expect(!lines(.sidebar).joined().stripped.contains("│"))
        #expect(!row(lines(.plain)).contains(accentIcon), "only a sidebar tints its icons")
    }

    @Test("A list item tint replaces the accent in a sidebar; monochrome is the secondary foreground")
    func listItemTint() {
        let red = row(lines(.sidebar, tint: .fixed(.red)))
        #expect(red.contains(ANSIRenderer.colorize("*", foreground: Color.red.opaqueSpelling)), "\(red.debugDescription)")
        let gray = row(lines(.sidebar, tint: .monochrome))
        #expect(
            gray.contains(ANSIRenderer.colorize("*", foreground: palette.foregroundSecondary.opaqueSpelling)),
            "\(gray.debugDescription)")
        // `nil` keeps what is inherited: the accent.
        let inherited = row(lines(.sidebar, tint: nil))
        #expect(inherited.contains(ANSIRenderer.colorize("*", foreground: palette.accent.opaqueSpelling)))
        #expect(ListItemTint.preferred(.blue) != .fixed(.blue))
    }
}
