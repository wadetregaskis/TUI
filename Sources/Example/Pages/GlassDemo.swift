//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Glass, beside the materials it is made of: each kind over a block of the
/// striped ramp the materials sit on, glass that touches drawn as one shape in
/// a container, and the two glass button styles.
///
/// Each sample is padded wider than its name, so the stripes show through the
/// glass on either side of it, tinted; the stripes are a column wider still
/// each side, to compare. The rim is drawn in the appearance's lines, so
/// cycling the appearance redraws it — rounded, square, heavy, double, dotted,
/// a band, or none.
struct GlassDemo: View {
    /// The ramp under the glass: the materials' and the gradients'.
    private static let ramp: [Color] = [.rgb(255, 80, 80), .rgb(80, 160, 255)]

    var body: some View {
        DemoSection("page.colors.section.glass") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.colors.glass.caption")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 1) {
                    Self.onStripes(".regular") { Self.sample(".regular").glassEffect() }
                    Self.onStripes(".clear") { Self.sample(".clear").glassEffect(.clear) }
                    Self.onStripes(".tint(.accent)") {
                        Self.sample(".tint(.accent)").glassEffect(.regular.tint(.palette.accent))
                    }
                    Self.onStripes(".interactive()") {
                        Self.sample(".interactive()").glassEffect(.regular.interactive())
                    }
                }
                Text("page.colors.glass.container")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 1) {
                    Self.onStripes(columns: 14) { Self.pair }
                    Self.onStripes(columns: 14) { GlassEffectContainer { Self.pair } }
                }
                HStack(spacing: 1) {
                    Self.onStripes(columns: 14, rows: 1) {
                        Button("page.colors.glass.button") {}
                            .buttonStyle(.glass)
                    }
                    Self.onStripes(columns: 20, rows: 1) {
                        Button("page.colors.glass.prominent") {}
                            .buttonStyle(.glassProminent)
                    }
                }
            }
        }
    }

    /// Two glasses side by side, touching.
    private static var pair: some View {
        HStack(spacing: 0) {
            sample("A").glassEffect()
            sample("B").glassEffect()
        }
    }

    /// `name` padded two cells either side and a row above and below: the
    /// room a glass's rim takes, and a cell inside it for what is behind to
    /// show through.
    private static func sample(_ name: String) -> some View {
        Text(verbatim: name).padding(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
    }

    /// `content` centred over a block of the striped ramp a column wider than
    /// a sample named `name` each side.
    private static func onStripes<Content: View>(
        _ name: String, @ViewBuilder content: () -> Content
    ) -> some View {
        onStripes(columns: name.count + 6, content: content)
    }

    /// `content` centred over a block of the striped ramp `columns` wide and
    /// `rows` tall.
    private static func onStripes<Content: View>(
        columns: Int, rows: Int = 3, @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { _ in
                    Text(verbatim: String(repeating: "▚", count: columns))
                        .foregroundStyle(LinearGradient(colors: ramp, startPoint: .leading, endPoint: .trailing))
                }
            }
            content()
        }
    }
}
