//  🖥️ TUI — A Terminal UI framework for Swift
//  ShadowsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Shadows: a radius ramp of cards casting onto a light panel, a label
/// casting its letters, a well pressed into the panel by a style's inner
/// shadow (`ShapeStyle.shadow(_:)`), and a coloured shadow as a glow on the
/// page.
///
/// The panel is there because a black shadow needs something to darken: on
/// the near-black pages the palettes draw, one at a third is barely a change.
///
/// Above them, a card and a label cast the shadow the controls state: its
/// colour, radius and offset, which are `shadow(color:radius:x:y:)`'s
/// parameters. SwiftUI's has no angle or distance: the offset is the pair of
/// cells, and the angle and distance are the one in polar form.
struct ShadowsDemo: View {
    /// The panel the cards cast onto.
    private static let panel = Color.rgb(176, 176, 188)

    /// The colours the controls offer, as `shadow(color:)` takes them.
    enum Ink: CaseIterable, Hashable {
        case faint, strong, red, accent

        /// The name's key.
        var key: String {
            switch self {
            case .faint: "page.colors.shadow.ink.faint"
            case .strong: "page.colors.shadow.ink.strong"
            case .red: "page.colors.shadow.ink.red"
            case .accent: "page.colors.shadow.ink.accent"
            }
        }

        var color: Color {
            switch self {
            case .faint: .black.opacity(0.33)
            case .strong: .black.opacity(0.7)
            case .red: .rgb(200, 30, 30).opacity(0.8)
            case .accent: Color.palette.accent.opacity(0.8)
            }
        }
    }

    @State private var ink = Ink.faint
    @State private var radius = 2
    @State private var offsetX = 2
    @State private var offsetY = 1

    var body: some View {
        DemoSection("page.colors.section.shadows") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.colors.shadow.caption")
                    .foregroundStyle(.palette.foregroundSecondary)
                controls
                VStack(alignment: .leading, spacing: 4) {
                    tryIt
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(0..<4, id: \.self) { radius in
                            card("\(radius)", fill: .rgb(250, 250, 250))
                                .shadow(radius: radius, x: 2, y: 1)
                        }
                    }
                    Text("page.colors.shadow.text")
                        .bold()
                        .foregroundStyle(Color.rgb(250, 250, 250))
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 1)
                    HStack(alignment: .top, spacing: 3) {
                        // A style's inner shadow: over the fill, under the label.
                        Text("page.colors.shadow.inner.label")
                            .foregroundStyle(Color.rgb(30, 30, 30))
                            .padding(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
                            .background(Color.rgb(250, 250, 250).shadow(.inner(radius: 1, x: 1, y: 1)))
                        Text("page.colors.shadow.inner")
                            .foregroundStyle(Color.rgb(30, 30, 30))
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 6))
                .background(Self.panel)
                HStack(spacing: 3) {
                    card("●", fill: .palette.accent)
                        .shadow(color: .palette.accent.opacity(0.8), radius: 2)
                    Text("page.colors.shadow.glow")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                // The glow reaches two rows (its radius) past the card, so two
                // rows below it keep it off the row above the next header.
                .padding(EdgeInsets(top: 1, leading: 3, bottom: 2, trailing: 0))
            }
        }
    }

    /// The shadow's parameters, as `shadow(color:radius:x:y:)` takes them.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("page.colors.shadow.try")
                .foregroundStyle(.palette.foregroundSecondary)
            HStack(spacing: 3) {
                Picker("page.colors.shadow.colour", selection: $ink) {
                    ForEach(Ink.allCases, id: \.self) { choice in
                        Text(verbatim: L(choice.key)).tag(choice)
                    }
                }
                Stepper("page.colors.shadow.radius", value: $radius, in: 0...8)
            }
            HStack(spacing: 3) {
                Stepper("page.colors.shadow.x", value: $offsetX, in: -6...6)
                Stepper("page.colors.shadow.y", value: $offsetY, in: -4...4)
            }
            Text(verbatim: ".shadow(color: …, radius: \(radius), x: \(offsetX), y: \(offsetY))")
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    /// A card and a label casting the shadow the controls state, onto the panel.
    private var tryIt: some View {
        HStack(alignment: .top, spacing: 6) {
            card("●", fill: .rgb(250, 250, 250))
                .shadow(color: ink.color, radius: radius, x: offsetX, y: offsetY)
            Text("page.colors.shadow.live")
                .bold()
                .foregroundStyle(Color.rgb(250, 250, 250))
                .shadow(color: ink.color, radius: radius, x: offsetX, y: offsetY)
        }
    }

    /// A small filled card with `label` in the middle of it.
    private func card(_ label: String, fill: Color) -> some View {
        Text(verbatim: label)
            .foregroundStyle(Color.rgb(30, 30, 30))
            .padding(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
            .background(fill)
    }
}
