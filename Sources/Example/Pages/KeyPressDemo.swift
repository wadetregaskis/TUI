//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyPressDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// `.onKeyPress`: a view of the app's own that answers keys while it holds
/// the focus — the arrows move a marker along a track, the digits typed are
/// kept — ahead of the keys' usual work (an arrow otherwise moves the focus).
/// An arrow that would take the marker past an end is refused, and says so
/// with the terminal's bell (`\.ringBell`), as TUI's own controls do.
struct KeyPressDemo: View {
    @State private var position = 0
    @State private var digits = ""
    @FocusState private var isFocused: Bool
    @Environment(\.ringBell) private var ringBell

    private static let trackLength = 20

    var body: some View {
        DemoSection("page.focus.keyPressSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.keyPressExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text(track)
                    .foregroundStyle(isFocused ? .palette.accent : .palette.foregroundSecondary)
                    .padding(.horizontal, 1)
                    .border(isFocused ? .palette.accent : .palette.border)
                    .focusable()
                    .focused($isFocused)
                    // Handled even at an end, so the arrow does not move the
                    // focus instead: refused, with the bell.
                    .onKeyPress(.leftArrow) {
                        if position == 0 { ringBell() } else { position -= 1 }
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        if position == Self.trackLength - 1 { ringBell() } else { position += 1 }
                        return .handled
                    }
                    .onKeyPress(characters: .decimalDigits) { press in
                        digits = String((digits + press.characters).suffix(8))
                        return .handled
                    }
                Text("\(L("page.focus.keyPressDigits")) \(digits.isEmpty ? "—" : digits)")
                    .foregroundStyle(.palette.foregroundSecondary)
            }
        }
    }

    /// The track, the marker where the arrows have put it.
    private var track: String {
        // `Character` stated: with literals alone, Swift 6.4.0 on static
        // Linux finds `String.init` ambiguous between the `Character`
        // sequence, `Unicode.Scalar` collection (`_RegexParser`'s) and
        // `RangeReplaceableCollection` overloads.
        String((0..<Self.trackLength).map { (index: Int) -> Character in index == position ? "●" : "·" })
    }
}
