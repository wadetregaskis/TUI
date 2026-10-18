//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Drop shadows: a radius ramp of cards casting onto a light panel, a label
/// casting its letters, and a coloured shadow as a glow on the page.
///
/// The panel is there because a black shadow needs something to darken: on
/// the near-black pages the palettes draw, one at a third is barely a change.
struct ShadowsDemo: View {
    /// The panel the cards cast onto.
    private static let panel = Color.rgb(176, 176, 188)

    var body: some View {
        DemoSection("page.colors.section.shadows") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.colors.shadow.caption")
                    .foregroundStyle(.palette.foregroundSecondary)
                VStack(alignment: .leading, spacing: 4) {
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
                }
                .padding(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 6))
                .background(Self.panel)
                HStack(spacing: 3) {
                    card("●", fill: .palette.accent)
                        .shadow(color: .palette.accent.opacity(0.8), radius: 2)
                    Text("page.colors.shadow.glow")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                .padding(EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 0))
            }
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
