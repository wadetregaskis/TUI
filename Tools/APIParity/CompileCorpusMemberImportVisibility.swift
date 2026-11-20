//  🖥️ TUI — A Terminal UI framework for Swift
//  CompileCorpusMemberImportVisibility.swift
//
//  SwiftUI source that must compile against TUI alone in a file built with the
//  `MemberImportVisibility` upcoming feature, which Swift 7 makes the default:
//  type-checked on its own by `compile_corpus.sh`, with that feature on. Under
//  it a member is visible only if its module is imported, and SwiftUI's import
//  chain gives such a file what `import SwiftUI` names; `import TUI` must give
//  the same.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// A paragraph's alignment with its types named. On the macOS 26 SDK they are
/// Core Text's own (the owner's ruling attralign, 2026-11-19), and the `TUI`
/// umbrella re-exports Core Text as `import SwiftUI` brings it; without that,
/// naming them fails with "missing import of defining module 'CoreText'"
/// (Tools/SwiftUIProbes/Paragraph attribute types (attralign)). On the 15 SDKs
/// they are TUI's.
@available(macOS 15, *)
@MainActor
private struct ParagraphAlignmentNamed: View {
    @State private var text = AttributedString("Chapter One")

    var body: some View {
        Button("Centre") {
            if #available(macOS 26, *) {
                let side: AttributedString.TextAlignment = .center
                text.alignment = side
                _ = text.runs.first?.alignment == .right
            }
            text.paragraphAlignment = .trailing
        }
    }
}
