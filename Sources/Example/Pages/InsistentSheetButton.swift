//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InsistentSheetButton.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// A sheet that wants an answer: `.interactiveDismissDisabled()` takes away
/// the ways of walking off — Escape, and a click outside — so only its own
/// buttons close it; and `.presentationSizing(.form)` gives it a form's size
/// rather than its content's.
///
/// Its own button with the sheet attached, where the page's other variants
/// hang theirs off the page: everything it needs is here in one place.
struct InsistentSheetButton: View {
    @State private var isPresented = false
    @State private var answer = "—"

    var body: some View {
        HStack(spacing: 1) {
            Button("page.overlays.variants.insistent") { isPresented = true }
            Text(answer).foregroundStyle(.palette.foregroundTertiary)
        }
        .sheet(isPresented: $isPresented) {
            Dialog(title: "page.overlays.variants.insistentTitle") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.overlays.variants.insistentBody")
                    HStack(spacing: 2) {
                        Spacer()
                        Button("page.overlays.variants.insistentDiscard", role: .destructive) {
                            answer = L("page.overlays.variants.insistentDiscarded")
                            isPresented = false
                        }
                        Button("page.overlays.variants.insistentKeep") {
                            answer = L("page.overlays.variants.insistentKept")
                            isPresented = false
                        }
                    }
                }
            }
            .presentationSizing(.form)
            .interactiveDismissDisabled()
        }
    }
}
