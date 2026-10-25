//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProgressClip.swift
//
//  `progress`: a deploy in flight — bars filling in several track styles,
//  gauges, an indeterminate bar, spinners turning — every one on the app's
//  own clock.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

@MainActor
let progressClip = Clip(
    id: "progress",
    title: "Progress",
    columns: 112,
    rows: 30,
    terminal: "iterm",
    script: [.camera(Shot(x: 1.3, y: 3.4, width: 56, height: 18.5)), .wait(9.0)],
    run: { await ProgressApp.main() }
)

struct ProgressApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Deploy") {
            DeployMonitor()
        }
    }
}

/// A deploy: four regions rolling out at their own paces, the fleet's load
/// beside them, and the steps still to come.
struct DeployMonitor: View {
    @State private var tick = 0

    private let regions: [(String, Int)] = [("eu-west", 3), ("us-east", 2), ("ap-south", 5), ("sa-east", 4)]
    private let styles: [TrackStyle] = [.blockFine, .shade, .dot, .braille]

    var body: some View {
        // A ten-second loop: every bar is back where it began when the clip loops.
        let phase = Double(tick % 100) / 100
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Spinner("Deploying build 1.0.418", style: .dots)
                Text(verbatim: "\(Int(phase * 100))%").foregroundStyle(.palette.foregroundSecondary)
            }
            GroupBox("Regions") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(regions.indices, id: \.self) { index in
                        let (name, pace) = regions[index]
                        let fraction = min(1, (phase * Double(pace + 2) / 4).truncatingRemainder(dividingBy: 1.0001))
                        HStack(spacing: 1) {
                            Text(verbatim: name).frame(width: 9, alignment: .leading)
                            ProgressView(value: fraction).trackStyle(styles[index])
                            Text(verbatim: "\(Int(fraction * 100))%").frame(width: 4, alignment: .trailing)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 2) {
                GroupBox("Load") {
                    HStack(spacing: 2) {
                        let cpu = 0.35 + 0.3 * abs(sin(phase * .pi * 2))
                        let memory = 0.6 + 0.25 * abs(cos(phase * .pi * 3))
                        Gauge(value: cpu) { Text(verbatim: "CPU") } currentValueLabel: {
                            Text(verbatim: "\(Int(cpu * 100))%")
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        Gauge(value: memory) { Text(verbatim: "Mem") } currentValueLabel: {
                            Text(verbatim: "\(Int(memory * 100))%")
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(.orange)
                    }
                }
                GroupBox("Next") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 1) { Spinner(style: .line); Text(verbatim: "Warming caches") }
                        HStack(spacing: 1) { Spinner(style: .moon); Text(verbatim: "Smoke tests") }
                        ProgressView().frame(width: 22)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 60, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Deploy · production") }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                tick += 1
            }
        }
    }
}
