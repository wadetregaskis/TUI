//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewPage+SplitViews.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension SplitViewPage {
    /// `HSplitView` and `VSplitView`: panes side by side or one above the
    /// other, with dividers the user moves — by dragging, or from the keyboard
    /// (Tab to a divider, then the arrows, Home and End). A pane's frame bounds it.
    var splitViewsSection: some View {
        DemoSection("page.splitView.hvSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.splitView.hvExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HSplitView {
                    pane("page.splitView.hv.left")
                        .frame(minWidth: 10, idealWidth: 20, maxWidth: 40)
                    VSplitView {
                        pane("page.splitView.hv.top")
                            .frame(minHeight: 2, idealHeight: 3)
                        pane("page.splitView.hv.bottom")
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
