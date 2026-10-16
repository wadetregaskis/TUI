//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyPressDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// `.onKeyPress`: a view of the app's own that answers keys while it holds
/// the focus — the arrows move a marker along a track, the digits typed are
/// kept — ahead of the keys' usual work (an arrow otherwise moves the focus).
struct KeyPressDemo: View {
    @State private var position = 0
    @State private var digits = ""
    @FocusState private var isFocused: Bool

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
                    .onKeyPress(.leftArrow) {
                        position = max(0, position - 1)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        position = min(Self.trackLength - 1, position + 1)
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
        String((0..<Self.trackLength).map { $0 == position ? "●" : "·" })
    }
}
