//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewCustomizationTests.swift
//
//  `TabViewCustomization` and `.tabViewCustomization(_:)`: a sidebar leaves
//  out the tabs a customization hides and lists tabs and sections in the
//  order it states; a strip is left alone; and the value itself — its
//  subscripts, resets and coding.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Tab view customization")
struct TabViewCustomizationTests {
    private func tabs(_ customization: TabViewCustomization, sidebar: Bool = true) -> [String] {
        let view = TabView {
            Tab("Inbox", systemImage: "tray") { Text("INBOX BODY") }
                .customizationID("inbox")
            Tab("Drafts", systemImage: "doc") { Text("DRAFTS BODY") }
                .customizationID("drafts")
            TabSection("Folders") {
                Tab("Work", systemImage: "folder") { Text("WORK BODY") }
                    .customizationID("work")
                Tab("Home", systemImage: "folder") { Text("HOME BODY") }
                    .customizationID("home")
            }
            .customizationID("folders")
            TabSection("Tags") {
                Tab("Red", systemImage: "tag") { Text("RED BODY") }
                    .customizationID("red")
            }
            .customizationID("tags")
        }
        .tabViewCustomization(.constant(customization))
        let styled = sidebar ? AnyView(view.tabViewStyle(.sidebarAdaptable)) : AnyView(view)
        return renderToBuffer(styled, context: makeRenderContext(width: 90, height: 14)).lines.map(\.stripped)
    }

    /// The row each name is drawn on, top to bottom, of those drawn.
    private func order(_ names: [String], in lines: [String]) -> [String] {
        names.compactMap { name in lines.firstIndex { $0.contains(name) }.map { (name, $0) } }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }

    private func decoded(_ json: String) throws -> TabViewCustomization {
        try JSONDecoder().decode(TabViewCustomization.self, from: Data(json.utf8))
    }

    @Test("A tab the customization hides leaves the sidebar, and stays in a strip, as measured")
    func hiddenTab() {
        var customization = TabViewCustomization()
        customization[tab: "drafts"].sidebarVisibility = .hidden
        let sidebar = tabs(customization).joined(separator: "\n")
        #expect(!sidebar.contains("Drafts") && sidebar.contains("Inbox"), "\(sidebar)")
        let strip = tabs(customization, sidebar: false).joined(separator: "\n")
        #expect(strip.contains("Drafts"), "\(strip)")
    }

    @Test("A section's stated tab order and the stated section order arrange the sidebar")
    func statedOrders() throws {
        let natural = order(["Inbox", "Drafts", "Folders", "Work", "Home", "Tags", "Red"], in: tabs(TabViewCustomization()))
        #expect(natural == ["Inbox", "Drafts", "Folders", "Work", "Home", "Tags", "Red"])
        let customization = try decoded(#"{"tabOrder": {"folders": ["home", "work"]}, "sectionOrder": ["tags", "folders"]}"#)
        #expect(customization[section: "folders"].tabOrder == ["home", "work"])
        let arranged = order(["Inbox", "Drafts", "Folders", "Work", "Home", "Tags", "Red"], in: tabs(customization))
        #expect(arranged == ["Inbox", "Drafts", "Tags", "Red", "Folders", "Home", "Work"], "\(arranged)")
    }

    @Test("The value reads .automatic and nil until set, forgets .automatic, and resets")
    func subscriptsAndResets() throws {
        var customization = TabViewCustomization()
        #expect(customization[tab: "inbox"].sidebarVisibility == .automatic)
        #expect(customization[section: "folders"].tabOrder == nil)
        customization[tab: "inbox"].sidebarVisibility = .hidden
        #expect(customization[tab: "inbox"].sidebarVisibility == .hidden)
        customization[tab: "inbox"].sidebarVisibility = .automatic
        #expect(customization == TabViewCustomization())
        customization[tab: "inbox"].sidebarVisibility = .visible
        customization.resetVisibility()
        #expect(customization == TabViewCustomization())

        var ordered = try decoded(#"{"tabOrder": {"folders": ["home"]}, "sectionOrder": ["tags"]}"#)
        ordered[section: "folders"].resetTabOrder()
        #expect(ordered[section: "folders"].tabOrder == nil)
        ordered.resetSectionOrder()
        #expect(ordered == TabViewCustomization())
    }

    @Test("It encodes and decodes to the same value")
    func coding() throws {
        var customization = try decoded(#"{"tabOrder": {"folders": ["home", "work"]}, "sectionOrder": ["tags"]}"#)
        customization[tab: "inbox"].sidebarVisibility = .hidden
        customization[tab: "red"].sidebarVisibility = .visible
        let data = try JSONEncoder().encode(customization)
        #expect(try JSONDecoder().decode(TabViewCustomization.self, from: data) == customization)
    }

    @Test("A default visibility for .tabBar or .automatic hides nothing, as measured on macOS")
    func defaultVisibilityHidesNothing() {
        for placement in [AdaptableTabBarPlacement.tabBar, .automatic] {
            let view = TabView {
                Tab("Inbox", systemImage: "tray") { Text("INBOX BODY") }
                Tab("Spare", systemImage: "doc") { Text("SPARE BODY") }
                    .defaultVisibility(.hidden, for: placement)
                    .customizationBehavior(.automatic, for: placement)
            }
            for styled in [AnyView(view), AnyView(view.tabViewStyle(.sidebarAdaptable))] {
                let drawn = renderToBuffer(styled, context: makeRenderContext(width: 60, height: 8)).lines
                    .map(\.stripped).joined()
                #expect(drawn.contains("Spare"), "\(drawn)")
            }
        }
    }
}
