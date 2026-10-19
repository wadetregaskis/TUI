//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedGeometryDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Views that share an id in a namespace share their geometry
/// (`matchedGeometryEffect`): a chip carried from one list to the other, a
/// card growing into its detail and back, and a bar following the tab picked
/// — each under the page's own curve.
struct MatchedGeometryDemo: View {
    /// The page's animation, from the settings at its top.
    let animation: Animation

    @Namespace private var space
    @State private var toDo = ["α", "β", "γ", "δ"]
    @State private var done = ["ε"]
    @State private var expanded = false
    @State private var tab = 0

    /// The tabs the bar follows.
    private static let tabs: [LocalizedStringKey] = [
        "page.animation.matched.tab.day",
        "page.animation.matched.tab.week",
        "page.animation.matched.tab.month",
    ]

    var body: some View {
        DemoSection("page.animation.section.matched") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.matched.explain")
                    .foregroundStyle(.palette.foregroundSecondary)
                chips
                card
                tabBar
            }
        }
    }

    // MARK: - A chip between two lists

    /// Two lists, and the buttons that move a chip from one to the other. A
    /// chip keeps its id in either list, so the one that appears is carried
    /// from where the one that went was drawn; it is the same size in both,
    /// so it is only moved.
    private var chips: some View {
        HStack(alignment: .top, spacing: 2) {
            list("page.animation.matched.toDo", chips: toDo)
            VStack(alignment: .leading, spacing: 0) {
                Button("page.animation.matched.finish") {
                    withAnimation(animation) {
                        guard !toDo.isEmpty else { return }
                        done.append(toDo.removeFirst())
                    }
                }
                Button("page.animation.matched.reopen") {
                    withAnimation(animation) {
                        guard !done.isEmpty else { return }
                        toDo.insert(done.removeLast(), at: 0)
                    }
                }
            }
            list("page.animation.matched.done", chips: done)
        }
    }

    private func list(_ title: LocalizedStringKey, chips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold()
            ForEach(chips, id: \.self) { chip in
                Text(verbatim: " \(chip) ")
                    .foregroundStyle(.palette.background)
                    .background(.palette.accent)
                    .matchedGeometryEffect(id: chip, in: space)
            }
        }
        .frame(width: 14, height: 7, alignment: .topLeading)
        .padding(.horizontal, 1)
        .border()
    }

    // MARK: - A card and its detail

    /// One view or the other, with one id: the detail grows from the card,
    /// laid out again at every size between, and shrinks back into it. Each
    /// fills the frame it is matched to, so each frame between shows a box.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("page.animation.matched.cardTitle").bold()
                    Text("page.animation.matched.cardDetail")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 1)
                .border()
                .matchedGeometryEffect(id: "card", in: space)
                .frame(width: 44, height: 6)
            } else {
                Text("page.animation.matched.cardTitle").bold()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 1)
                    .border()
                    .matchedGeometryEffect(id: "card", in: space)
                    .frame(width: 16, height: 3)
            }
            Button(expanded ? "page.animation.matched.collapse" : "page.animation.matched.expand") {
                withAnimation(animation) { expanded.toggle() }
            }
        }
    }

    // MARK: - A bar under the tab picked

    /// The bar follows the tab whose id it is given: its top edge on the
    /// tab's bottom edge (the two anchors), the tab's width. It is laid out
    /// as a row of its own under the tabs, and only drawn where its tab is.
    private var tabBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Self.tabs.indices, id: \.self) { index in
                    Button(Self.tabs[index]) {
                        withAnimation(animation) { tab = index }
                    }
                    .matchedGeometryEffect(id: index, in: space, anchor: .bottom)
                }
            }
            Color.accentColor
                .frame(height: 1)
                .matchedGeometryEffect(id: tab, in: space, anchor: .top, isSource: false)
        }
    }
}
