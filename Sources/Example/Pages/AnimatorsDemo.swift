//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatorsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Animations that run themselves: a `PhaseAnimator` cycling through phases,
/// one run through its phases when a trigger changes, a `KeyframeAnimator`
/// playing a spring and a line, and a number changed two ways: one whose
/// changed digits dissolve to their new value
/// (`.contentTransition(.numericText())`, which is SwiftUI's rolling digits:
/// it never shows the values between), and one that counts through every
/// value on the way, its value itself animated (``CountingText``).
struct AnimatorsDemo: View {
    @State private var pings = 0
    @State private var bounces = 0
    @State private var count = 0

    var body: some View {
        DemoSection("page.animation.section.animators") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.animators.explain")
                    .foregroundStyle(.palette.foregroundSecondary)
                // Cycles for as long as it is drawn.
                HStack(spacing: 2) {
                    Text("page.animation.animators.cycling")
                        .frame(width: 18, alignment: .leading)
                    PhaseAnimator([0, 8, 16, 8]) { position in
                        Text("●").foregroundStyle(.palette.accent).offset(x: position)
                    } animation: { _ in
                        .easeInOut(duration: 0.4)
                    }
                    .frame(width: 18, alignment: .leading)
                }
                // Runs through the phases once each time the trigger changes.
                HStack(spacing: 2) {
                    Button("page.animation.animators.ping") { pings += 1 }
                        .frame(width: 18, alignment: .leading)
                    PhaseAnimator([false, true, false], trigger: pings) { lit in
                        Text("page.animation.animators.pinged")
                            .foregroundStyle(lit ? .palette.accent : .palette.foregroundTertiary)
                            .bold(lit)
                    }
                }
                // A spring out to 20 cells and a line back.
                HStack(spacing: 2) {
                    Button("page.animation.animators.bounce") { bounces += 1 }
                        .frame(width: 18, alignment: .leading)
                    KeyframeAnimator(initialValue: 0.0, trigger: bounces) { value in
                        Text("◆").foregroundStyle(.palette.accent).offset(x: Int(value.rounded()))
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(20, duration: 0.6)
                            LinearKeyframe(0, duration: 0.5)
                        }
                    }
                    .frame(width: 24, alignment: .leading)
                }
                // The same change twice: the digits that change dissolve, or
                // the number counts there.
                HStack(spacing: 2) {
                    Button("+1") { withAnimation { count += 1 } }
                    Button("+10") { withAnimation { count += 10 } }
                    Text("page.animation.animators.dissolves")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("\(count)")
                        .bold()
                        .contentTransition(.numericText())
                        .frame(width: 4, alignment: .leading)
                    Text("page.animation.animators.counts")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: "")
                        .modifier(CountingText(value: Double(count)))
                }
            }
        }
    }
}

/// A number drawn at every whole value it passes on its way to a new one: the
/// value itself is the animatable data, so under `withAnimation` it is
/// interpolated frame by frame and drawn rounded — "+10" shows 1, 2, 3 … 10
/// as fast as the frames come. The way SwiftUI counts a number up, as an
/// `Animatable` modifier; `numericText` does not count, it rolls (here,
/// dissolves) the digits that change.
private struct CountingText: ViewModifier, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(verbatim: "\(Int(value.rounded()))").bold()
    }
}
