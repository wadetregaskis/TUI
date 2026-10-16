//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RedactionAndSelectionDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Two things a view's text can be told: to draw as a placeholder while its
/// content is not ready (`.redacted(reason: .placeholder)`, with `.unredacted()`
/// for the part that is), and where a drag selects it (`.textSelection`).
struct RedactionAndSelectionDemo: View {
    @State private var isLoading = true

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            DemoSection("page.textStyles.section.redacted") {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("page.textStyles.redacted.loading", isOn: $isLoading)
                    VStack(alignment: .leading, spacing: 0) {
                        // Known before the rest arrives, so never redacted.
                        Text("page.textStyles.redacted.heading").bold().unredacted()
                        Text("Ada Lovelace")
                        Text("12 St James's Square, London")
                        Text("ada@example.com").foregroundStyle(.palette.accent)
                    }
                    .padding(.horizontal, 1)
                    .border(.palette.border)
                    .redacted(reason: isLoading ? .placeholder : [])
                }
            }
            DemoSection("page.textStyles.section.selection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.textStyles.selection.explain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A drag selects within this text, and no further.
                    Text("page.textStyles.selection.enabled")
                        .textSelection(.enabled)
                    // A drag here selects nothing: TUIkit's selection is off.
                    Text("page.textStyles.selection.disabled")
                        .foregroundStyle(.palette.foregroundTertiary)
                        .textSelection(.disabled)
                }
            }
        }
    }
}
