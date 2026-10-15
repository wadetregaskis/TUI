//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarSpacerAndGroupTests.swift
//
//  The two toolbar content types that are not one item: `ToolbarSpacer`,
//  which spaces the items either side of it — the room the bar has to spare
//  when it is flexible, one column when it is fixed — and `ToolbarItemGroup`,
//  whose views sit side by side in the bar its placement names.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Two trailing items with a spacer of `sizing` between them, or none.
private struct SpacedApp: App {
    var sizing: SpacerSizing?

    init() {}

    init(sizing: SpacerSizing?) { self.sizing = sizing }

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("AAA") }
                    if let sizing {
                        ToolbarSpacer(sizing, placement: .primaryAction)
                    }
                    ToolbarItem(placement: .primaryAction) { Text("ZZZ") }
                }
        }
    }
}

/// A group in the top bar and a group in the bottom bar.
private struct GroupsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Text("G1")
                        Text("G2")
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Text("B1")
                        Text("B2")
                    }
                }
        }
    }
}

@MainActor
@Suite("Toolbar spacers and groups", .serialized)
struct ToolbarSpacerAndGroupTests {

    /// The screen two frames in, escapes stripped: one to declare, one to draw.
    private func screen(_ app: some App, width: Int = 60, height: Int = 10) -> [String] {
        let headless = HeadlessApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        return headless.screen.map(\.stripped)
    }

    /// The columns between the end of `AAA` and the start of `ZZZ` on the row
    /// that holds both, or `nil` when no row does.
    private func gap(_ rows: [String]) -> Int? {
        guard let row = rows.first(where: { $0.contains("AAA") && $0.contains("ZZZ") }),
            let lead = row.range(of: "AAA"), let trail = row.range(of: "ZZZ")
        else { return nil }
        return row.distance(from: lead.upperBound, to: trail.lowerBound)
    }

    @Test("A flexible spacer takes a share of the room the bar has to spare")
    func flexibleSpacerPushesItemsApart() {
        let plain = gap(screen(SpacedApp(sizing: nil)))
        let spaced = gap(screen(SpacedApp(sizing: .flexible)))
        #expect(plain == 1, "sanity: items one column apart without a spacer")
        // The bar's content is 56 columns wide (60, less a wall and a column of
        // air each side). The items take 6 and the row's three gaps 3 (after
        // the row's own spacer, and either side of this one), and the two
        // spacers split the other 47 — 24 to the first, 23 to this one — so 23
        // and its two gaps lie between the items.
        #expect(spaced == 25, "the spacer's share and the gaps round it: \(screen(SpacedApp(sizing: .flexible)))")
    }

    @Test("A fixed spacer is one column, between the items' own gaps")
    func fixedSpacerIsOneColumn() {
        #expect(gap(screen(SpacedApp(sizing: .fixed))) == 3)
    }

    @Test("A group's views sit side by side, one column apart, in the bar its placement names")
    func groupsSitSideBySide() {
        let rows = screen(GroupsApp())
        let top = rows.firstIndex { $0.contains("G1 G2") }
        let bottom = rows.firstIndex { $0.contains("B1 B2") }
        #expect(top != nil, "\(rows)")
        #expect(bottom != nil, "\(rows)")
        #expect(top.map { $0 < 3 } == true, "the top bar: \(rows)")
        #expect(bottom.map { $0 > rows.count - 4 } == true, "the bottom bar: \(rows)")
    }
}
