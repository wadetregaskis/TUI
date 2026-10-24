// TEXTFMT (2026-10-24): whether an alert's title and message keep a live value
// live. A WindowGroup app presents an alert whose title and message each hold
// a timer, and reads the alert panel's text fields at three times.
import AppKit
import SwiftUI

@MainActor func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
let start = Date()

@MainActor func texts(_ window: NSWindow) -> [String] {
    (window.contentView.map(views) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
}

@main struct ProbeApp: App {
    init() {
        Task { @MainActor in
            for time in [1.0, 3.0, 5.0] {
                try? await Task.sleep(for: .seconds(time - Date().timeIntervalSince(start)))
                for window in NSApp.windows where window.isVisible && !texts(window).isEmpty {
                    print(String(format: "t=%.1f", time), type(of: window), texts(window))
                }
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup {
            Text("body")
                .frame(width: 300, height: 200)
                .alert(Text("Alert \(start, style: .timer)"), isPresented: .constant(true)) {
                    Button("OK") {}
                } message: {
                    Text("Message \(start, style: .timer)")
                }
        }
    }
}
