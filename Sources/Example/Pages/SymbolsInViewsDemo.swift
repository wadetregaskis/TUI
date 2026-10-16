//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SymbolsInViewsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// SF Symbols where SwiftUI puts them: `Label(_:systemImage:)`,
/// `Image(systemName:)`, a `Menu` with a symbol, and — on a Mac, where the
/// Symbols framework is — `.symbolEffect`, of which a glyph in one cell can
/// show the two that breathe: pulse and breathe.
///
/// A symbol draws only in a terminal whose font has it (the SF Symbols font
/// installed, an Apple terminal font). Without it, a `Label` keeps its title
/// and closes the gap, while a bare `Image` draws nothing at all.
struct SymbolsInViewsDemo: View {
    @State private var pulses = true
    @State private var taps = 0

    var body: some View {
        DemoSection("page.emoji.symbolsInViews") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.emoji.symbolsInViewsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 3) {
                    Label("page.emoji.symbols.favourites", systemImage: "star.fill")
                    Label("page.emoji.symbols.done", systemImage: "checkmark.circle")
                        .foregroundStyle(.palette.success)
                    HStack(spacing: 1) {
                        Image(systemName: "folder")
                        Image(systemName: "document")
                        Image(systemName: "trash")
                    }
                    Menu("page.emoji.symbols.share", systemImage: "square.and.arrow.up") {
                        Button("page.emoji.symbols.copyLink") {}
                        Button("page.emoji.symbols.mail") {}
                    }
                }
                effects
            }
        }
    }

    /// `.symbolEffect`, where it exists: macOS only, as Apple's Symbols
    /// framework is.
    @ViewBuilder private var effects: some View {
        #if canImport(Symbols)
            HStack(spacing: 3) {
                Toggle("page.emoji.symbols.pulse", isOn: $pulses)
                Image(systemName: "heart.fill")
                    .foregroundStyle(.palette.error)
                    .symbolEffect(.pulse, isActive: pulses)
                // A discrete effect: one pulse each time the value changes.
                Button("page.emoji.symbols.ring") { taps += 1 }
                Image(systemName: "bell.fill")
                    .symbolEffect(.pulse, value: taps)
            }
        #endif
    }
}
