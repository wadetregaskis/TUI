//  🖥️ TUI — A Terminal UI framework for Swift
//  RedactionAndSelectionDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// Two things a view's text can be told: to draw as a placeholder while its
/// content is not ready (`.redacted(reason: .placeholder)`, with `.unredacted()`
/// for the part that is) or to hide what is private
/// (`.redacted(reason: .privacy)` reaching only `.privacySensitive()` views),
/// and where a drag selects it (`.textSelection`).
struct RedactionAndSelectionDemo: View {
    @State private var isLoading = true
    @State private var hidesPrivate = false
    /// Whether the loading skeleton shows it is still at work: now and then, a
    /// glint running across it (the owner, 2026-10-28).
    @State private var showsActivity = true

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
                    Toggle("page.textStyles.redacted.activity", isOn: $showsActivity)
                        .disabled(!isLoading)
                    Toggle("page.textStyles.redacted.private", isOn: $hidesPrivate)
                    if isLoading, showsActivity {
                        // Redrawn every frame only while it can glint.
                        TimelineView(.animation) { context in
                            card.textRenderer(LoadingGlint(time: context.date.timeIntervalSinceReferenceDate))
                        }
                    } else {
                        card
                    }
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

    /// The card, redacted as the toggles say.
    private var card: some View {
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
}

/// A glint running along each line of a loading skeleton every few seconds: a
/// few cells brightened, the brightest in the middle, to say the content is on
/// its way. Subtle, and mostly still.
private struct LoadingGlint: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// Seconds between glints, and how long one takes to cross.
    private static let period = 3.0
    private static let crossing = 0.8

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let elapsed = time.truncatingRemainder(dividingBy: Self.period)
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    // Where the glint is, in glyphs, running from before the
                    // line to past a 30-cell one.
                    let centre = elapsed / Self.crossing * 34 - 2
                    let distance = abs(Double(index) - centre)
                    var lit = ctx
                    if distance < 3 { lit.addFilter(.brightness(0.25 * (1 - distance / 3))) }
                    lit.draw(glyph)
                    index += 1
                }
            }
        }
    }
}
