//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutPage+Grids.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

extension LayoutPage {
    /// The swatch names the lazy grids flow — short words of different
    /// lengths, so the columns visibly fit the widest of them.
    static let gridWords = [
        "amber", "teal", "rust", "ivory", "plum", "sage", "coral", "slate", "olive", "navy",
        "mint", "ochre", "rose", "ink", "sand", "moss", "lilac", "steel", "peach", "jade",
    ]

    /// `LazyVGrid` and `LazyHGrid`: views flowed into tracks a `GridItem` sizes —
    /// fixed, flexible, or as many adaptive columns as fit. Lazy as their stack
    /// twins are: in a scroll view only the rows on screen are built.
    var lazyGridsSection: some View {
        DemoSection("page.layout.section.lazyGrids") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.layout.lazyGridsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                // As many 8-cell columns as the width allows: narrow the window
                // and the grid reflows.
                Text("page.layout.lazyGridsAdaptive").bold()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 8), spacing: 1)], alignment: .leading) {
                        ForEach(Self.gridWords, id: \.self) { word in
                            Text(word).foregroundStyle(.palette.accent)
                        }
                    }
                }
                .frame(height: 4)
                .border(.palette.border)
                // A fixed first column, a flexible second, and a third that
                // takes what is left.
                Text("page.layout.lazyGridsFixedFlexible").bold()
                LazyVGrid(
                    columns: [GridItem(.fixed(4)), GridItem(.flexible(minimum: 6, maximum: 12)), GridItem()],
                    alignment: .leading, spacing: 0
                ) {
                    ForEach(0..<6, id: \.self) { index in
                        Text("\(index + 1)").foregroundStyle(.palette.foregroundTertiary)
                        Text(Self.gridWords[index])
                        Text(Self.gridWords[index + 6]).foregroundStyle(.palette.foregroundSecondary)
                    }
                }
                // Wide enough for the flexible column to reach its maximum and
                // the last to take a visibly larger share of what is left; at
                // its own width the grid is only as wide as its words.
                .frame(width: 40)
                .border(.palette.border)
                // Rows instead of columns: two of them, filled down then across,
                // in a scroll view that scrolls sideways.
                Text("page.layout.lazyGridsRows").bold()
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.fixed(1)), GridItem(.fixed(1))], spacing: 2) {
                        ForEach(Self.gridWords, id: \.self) { word in
                            Text(word)
                        }
                    }
                }
                // Two rows, and one for the scroll bar along the bottom.
                .frame(width: 40, height: 3)
                .border(.palette.border)
            }
        }
    }

    /// `Group(subviews:transform:)`: a container of the app's own, which takes
    /// whatever views it is given apart and lays each out itself — here a
    /// numbered list, with a count of how many it was given.
    var subviewsSection: some View {
        DemoSection("page.layout.section.subviews") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.layout.subviewsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                NumberedList {
                    Text("page.layout.subviewsFirst")
                    Text("page.layout.subviewsSecond")
                    ForEach(0..<2, id: \.self) { index in
                        Text("\(L("page.layout.subviewsLooped")) \(index + 1)")
                    }
                }
            }
        }
    }
}

/// A container that numbers the views it is given — built on
/// `Group(subviews:transform:)`, which hands it its content's members one by
/// one: two `Text`s and a two-row `ForEach` are four.
private struct NumberedList<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { subviews in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(subviews.enumerated()), id: \.offset) { entry in
                    HStack(spacing: 1) {
                        Text("\(entry.offset + 1).").foregroundStyle(.palette.accent)
                        entry.element
                    }
                }
                Text("\(subviews.count) \(L("page.layout.subviewsCount"))")
                    .foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }
}
