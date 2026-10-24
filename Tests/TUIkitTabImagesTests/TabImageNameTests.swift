//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabImageNameTests.swift
//
//  `Tab(_:image:…)` with an image resource's name (owner, TAB-IMAGE-NAME,
//  option a, placed in TUIkitTabImages by option 2): the name is found as
//  `Image(_:bundle:)` finds it, as `Label(_:image:)`'s is; the picture shows
//  in a sidebar's row, and a strip's chip shows only the title.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitBitmaps
@testable import TUIkitFoundation
import TUIkitTabImages
@testable import TUIkitTabs
@testable import TUIkitTestSupport

@MainActor
@Suite("Tabs with an image resource's name")
struct TabImageNameTests {

    @Test("Every form names the image the bundle initialiser would")
    func everyFormNamesTheResource() {
        let wanted = Image("gear")
        #expect(Tab("Gear", image: "gear") { Text("body") }.label.image == wanted)
        #expect(Tab("Gear", image: "gear", role: nil) { Text("body") }.label.image == wanted)
        #expect(Tab("Gear", image: "gear", value: 1) { Text("body") }.label.image == wanted)
        #expect(Tab("Gear", image: "gear", value: 1, role: nil) { Text("body") }.label.image == wanted)
        let title = String("Gear")
        #expect(Tab(title, image: "gear") { Text("body") }.label.image == wanted)
        #expect(Tab(title, image: "gear", value: 1) { Text("body") }.label.image == wanted)
        let optional: Tab<Int?, Text, DefaultTabLabel> = Tab("Gear", image: "gear", value: 1) { Text("body") }
        #expect(optional.label.image == wanted)
        #expect(optional.value == 1)
    }

    @Test("A name finds the image file among the bundle's resources")
    func findsTheFile() throws {
        let fixture = try BitmapFixture(width: 4, height: 4)
        // The main bundle of a test run is the test tool's, which holds no
        // fixture; a path is what `Image(_:bundle:)` falls back to, so the
        // fixture's own path finds it as a resource name would.
        let tab = Tab("Pic", image: fixture.path) { Text("body") }
        #expect(tab.label.image == Image(fixture.path))
        #expect(tab.label.image == Image(.file(fixture.path)))
    }

    private func tabs(sidebar: Bool) -> some View {
        let view = TabView {
            Tab("Gear", image: "tuikit-test-missing-image") { Text("GEAR BODY") }
            Tab("Plain", systemImage: "tuikit-no-such-symbol") { Text("PLAIN BODY") }
        }
        return Group {
            if sidebar { view.tabViewStyle(.sidebarAdaptable) } else { view }
        }
    }

    @Test("A sidebar's row draws the picture in two cells before the title")
    func sidebarDrawsThePicture() throws {
        let harness = InputChainHarness(width: 40, height: 6)
        let lines = harness.frame(tabs(sidebar: true)).lines.map(\.stripped)
        let gear = try #require(lines.first { $0.contains("Gear") })
        let plain = try #require(lines.first { $0.contains("Plain") })
        let column = { (line: String, title: String) in
            line.distance(from: line.startIndex, to: line.range(of: title)!.lowerBound)
        }
        // Two cells of picture and the label's gap before the title, where a
        // title alone starts at the row's edge.
        #expect(column(gear, "Gear") == column(plain, "Plain") + 3, "\(lines)")
    }

    @Test("A strip's chip shows only the title")
    func stripShowsTheTitle() {
        let harness = InputChainHarness(width: 40, height: 4)
        let strip = harness.frame(tabs(sidebar: false)).lines.map(\.stripped).first ?? ""
        let plain = harness.frame(
            TabView(selection: .constant(0)) {
                Tab("Gear", value: 0) { Text("GEAR BODY") }
                Tab("Plain", value: 1) { Text("PLAIN BODY") }
            }
        ).lines.map(\.stripped).first ?? ""
        #expect(strip == plain)
    }
}
