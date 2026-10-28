//  🖥️ TUI — A Terminal UI framework for Swift
//  AspectReviewClip.swift
//
//  `aspectreview`: not a README clip — a scene for the owner to compare how a
//  terminal-graphics picture is drawn while its box is resized (PICTURE-ASPECT,
//  2026-10-28). On the left a picture resized a column at a time, keeping the
//  pixels already sent where the build lets it; on the right the same picture
//  sent fresh at every size, which is what the box should look like. Film it
//  under each build being compared:
//
//      Tools/ScreenClips/regenerate.sh aspectreview --terminal ghostty
//
//  → / ← widen and narrow both boxes by a column; the script grows them from
//  12 to 32 columns, holds, and shrinks them back.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

@MainActor
let aspectReviewClip = Clip(
    id: "aspectreview",
    title: "A picture resized (review)",
    columns: 87,
    rows: 25,
    output: 800,
    script: aspectReviewScript,
    run: { await AspectReviewApp.main() }
)

/// Grow a column every 0.3 s from 12 to 32, hold, then shrink back, and hold.
@MainActor
private let aspectReviewScript: [Step] = {
    var steps: [Step] = [.wait(1.5)]
    for _ in 0..<20 { steps += [.right, .wait(0.3)] }
    steps.append(.wait(1.5))
    for _ in 0..<20 { steps += [.left, .wait(0.3)] }
    steps.append(.wait(1.5))
    return steps
}()

struct AspectReviewApp: App {
    var body: some Scene {
        WindowGroup("TUI · A picture resized") {
            AspectReview()
                .palette(AppleTerminalPalette(.novel))
        }
    }
}

/// The two boxes, side by side, a column wider or narrower on → and ←.
struct AspectReview: View {
    @State private var width = 12

    /// The boxes' height in rows: fixed, so only their aspect changes.
    private static let height = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "Box \(width) × \(Self.height) cells").bold()
            HStack(alignment: .top, spacing: 3) {
                panel("Resized") { picture }
                // A new view at every size: its pixels are always sent afresh.
                panel("Sent fresh") { picture.id(width) }
            }
        }
        .padding(1)
        .focusable()
        .onKeyPress(.rightArrow) {
            width = min(36, width + 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            width = max(6, width - 1)
            return .handled
        }
    }

    private var picture: some View {
        Image(.file(ClipAssets.photo("galago")))
            .resizable()
            .scaledToFit()
            .frame(width: width, height: Self.height)
            .border()
    }

    private func panel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title).foregroundStyle(.palette.foregroundSecondary)
            content()
        }
        .frame(width: 38, alignment: .leading)
    }
}
