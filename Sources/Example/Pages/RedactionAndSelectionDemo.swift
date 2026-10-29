//  🖥️ TUI — A Terminal UI framework for Swift
//  RedactionAndSelectionDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Two things a view's text can be told: to draw as a placeholder while its
/// content is not ready (`.redacted(reason: .placeholder)`, with `.unredacted()`
/// for the part that is) or to hide what is private
/// (`.redacted(reason: .privacy)` reaching only `.privacySensitive()` views),
/// and where a drag selects it (`.textSelection`).
struct RedactionAndSelectionDemo: View {
    @State private var isLoading = true
    @State private var hidesPrivate = false

    /// Why the card is redacted: loading, hiding what is private, both or
    /// neither.
    private var reasons: RedactionReasons {
        var reasons: RedactionReasons = []
        if isLoading { reasons.insert(.placeholder) }
        if hidesPrivate { reasons.insert(.privacy) }
        return reasons
    }

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            DemoSection("page.textStyles.section.redacted") {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("page.textStyles.redacted.loading", isOn: $isLoading)
                    Toggle("page.textStyles.redacted.private", isOn: $hidesPrivate)
                    VStack(alignment: .leading, spacing: 0) {
                        // Known before the rest arrives, so never redacted.
                        Text("page.textStyles.redacted.heading").bold().unredacted()
                        Text("Ada Lovelace")
                        Text("12 St James's Square, London")
                        // Hidden under `.privacy` alone, as private data.
                        Text("ada@example.com").foregroundStyle(.palette.accent).privacySensitive()
                    }
                    .padding(.horizontal, 1)
                    .border(.palette.border)
                    .redacted(reason: reasons)
                }
                .indentedExamples()
            }
            DemoSection("page.textStyles.section.selection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.textStyles.selection.explain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        // A drag selects within this text, and no further.
                        Text("page.textStyles.selection.enabled")
                            .textSelection(.enabled)
                        // A drag here selects nothing: TUI's selection is off.
                        Text("page.textStyles.selection.disabled")
                            .foregroundStyle(.palette.foregroundTertiary)
                            .textSelection(.disabled)
                    }
                    .indentedExamples()
                }
            }
        }
    }
}
