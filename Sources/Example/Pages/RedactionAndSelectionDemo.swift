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
                            card(glintTime: context.date.timeIntervalSinceReferenceDate)
                        }
                    } else {
                        card(glintTime: nil)
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
    private func card(glintTime: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Known before the rest arrives, so never redacted.
            Text("page.textStyles.redacted.heading").bold().unredacted()
            placeholder("Ada Lovelace", glintTime: glintTime)
            placeholder("12 St James's Square, London", glintTime: glintTime)
            // Hidden under `.privacy` alone, as private data.
            placeholder("ada@example.com", glintTime: glintTime)
                .foregroundStyle(.palette.accent)
                .privacySensitive()
        }
        .padding(.horizontal, 1)
        .border(.palette.border)
        .redacted(reason: reasons)
    }

    @ViewBuilder
    private func placeholder(_ text: String, glintTime: Double?) -> some View {
        if let glintTime {
            Text(verbatim: text).textRenderer(LoadingGlint(time: glintTime, text: Array(text)))
        } else {
            Text(verbatim: text)
        }
    }
}

/// A glint running along each line of a loading skeleton every few seconds: a
/// few cells brightened and stepped through denser shade glyphs, the brightest
/// in the middle, to say the content is on its way. Subtle, and mostly still.
private struct LoadingGlint: TextRenderer {
    var time: Double
    let text: [Character]
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// Seconds between glints, and how long one takes to cross.
    private static let period = 2.0
    private static let crossing = 1.0

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let elapsed = time.truncatingRemainder(dividingBy: Self.period)
        // Where the glint is, in glyphs, running from before the
        // line to past a 30-cell one.
        let centre = elapsed / Self.crossing * 34 - 2
        for (index, glyph) in glyphs(of: layout) {
            let distance = abs(Double(index) - centre)
            guard distance < 3,
                let letter = character(of: glyph, in: text, layout: layout),
                !letter.isWhitespace
            else {
                ctx.draw(glyph)
                continue
            }
            var lit = ctx
            lit.addFilter(.brightness(0.5 * (1 - distance / 3)))
            lit.drawSubstituting(distance < 1 ? "▓" : "▒", for: glyph)
        }
    }
}
