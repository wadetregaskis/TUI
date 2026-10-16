//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutPage+SplitViews.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension LayoutPage {
    /// `HSplitView` and `VSplitView`: panes side by side or one above the
    /// other, with dividers the user moves — by dragging, or from the keyboard
    /// (Tab to a divider, then the arrows). A pane's frame bounds it.
    var splitViewsSection: some View {
        DemoSection("page.layout.section.splitViews") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.layout.splitViewsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HSplitView {
                    pane("page.layout.splitViews.left")
                        .frame(minWidth: 10, idealWidth: 20, maxWidth: 40)
                    VSplitView {
                        pane("page.layout.splitViews.top")
                            .frame(minHeight: 2, idealHeight: 3)
                        pane("page.layout.splitViews.bottom")
                            .frame(minHeight: 2)
                    }
                }
                .frame(height: 9)
                .border(.palette.border)
            }
        }
    }

    /// One pane: its name, centred in whatever room it has.
    private func pane(_ key: String) -> some View {
        Text(L(key))
            .foregroundStyle(.palette.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
