//  🖥️ TUI — A Terminal UI framework for Swift
//  PointerTrackingDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Following the pointer cell by cell (`.onContinuousHover`, where `.onHover`
/// says only in or out), and the modifier keys held (`.onModifierKeysChanged`
/// — which a terminal reports on its own only under the kitty keyboard
/// protocol; elsewhere they are seen when a key or a click carries them).
struct PointerTrackingDemo: View {
    @State private var position = "—"
    @State private var modifiers = "—"

    var body: some View {
        DemoSection("page.mouse.tracking") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.mouse.trackingExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("page.mouse.trackingArea")
                    .foregroundStyle(.palette.foregroundTertiary)
                    .frame(width: 40, height: 5)
                    .border(.palette.border)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): position = "(\(point.x), \(point.y))"
                        case .ended: position = "—"
                        }
                    }
                HStack(spacing: 3) {
                    ValueDisplayRow("page.mouse.trackingPointer", position)
                    ValueDisplayRow("page.mouse.trackingModifiers", modifiers)
                }
            }
        }
        .onModifierKeysChanged { _, held in
            modifiers = Self.describe(held)
        }
    }

    /// The modifiers held, as a menu writes them — `⌃⌥⇧⌘` — or a dash.
    private static func describe(_ held: EventModifiers) -> String {
        var symbols = ""
        if held.contains(.control) { symbols += "⌃" }
        if held.contains(.option) { symbols += "⌥" }
        if held.contains(.shift) { symbols += "⇧" }
        if held.contains(.command) { symbols += "⌘" }
        return symbols.isEmpty ? "—" : symbols
    }
}
