import AppKit
import SwiftUI

// Whether a later layer of a `ZStack` stops a click reaching a `Button` under
// it (bug hunt H-68, BLEND-9; owner ruling O-10 (a), 2026-11-21: a painted
// layer absorbs clicks as SwiftUI does, if this probe says SwiftUI does).
//
// Each case hosts `ZStack { button; layer }` in a 200 × 200 window and posts a
// press and a release at the window's centre, which is the button's centre,
// then prints whether the button's action ran. Every case runs with a bordered
// button (AppKit's control under SwiftUI) and a plain one (SwiftUI's own hit
// testing), the plain one's label a 120 × 40 grey field so that the centre is
// always inside it. `none` is the control: no layer, so the click lands. The
// last case has no layer and the button itself at `.opacity(0)`.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 covered.swift -o "$TMPDIR/covered"
//   "$TMPDIR/covered"

@MainActor var clicks = 0

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum Style: String, CaseIterable { case bordered, plain }

struct Covered<Layer: View>: View {
    let style: Style
    let layer: Layer
    var buttonOpacity = 1.0
    var body: some View {
        ZStack {
            Group {
                switch style {
                case .bordered:
                    Button("Save") { clicks += 1 }
                case .plain:
                    Button { clicks += 1 } label: { Color.gray.frame(width: 120, height: 40) }
                        .buttonStyle(.plain)
                }
            }
            .opacity(buttonOpacity)
            layer
        }
        .frame(width: 200, height: 200)
    }
}

@MainActor func mouse(_ window: NSWindow, _ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
}

let onScreen = ProcessInfo.processInfo.environment["PROBE_ONSCREEN"] != nil
@MainActor var keep: [NSWindow] = []

@MainActor func run<Layer: View>(_ label: String, _ layer: Layer, buttonOpacity: Double = 1) async {
    for style in Style.allCases {
        clicks = 0
        let host = NSHostingView(rootView: Covered(style: style, layer: layer, buttonOpacity: buttonOpacity))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        let origin = onScreen ? CGPoint(x: 80, y: 80) : CGPoint(x: -5000, y: -5000)
        let window = KeyableWindow(
            contentRect: NSRect(origin: origin, size: host.frame.size), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        keep.append(window)
        try? await Task.sleep(for: .milliseconds(350))
        NSApp.postEvent(mouse(window, .leftMouseDown), atStart: false)
        NSApp.postEvent(mouse(window, .leftMouseUp), atStart: false)
        try? await Task.sleep(for: .milliseconds(500))
        let hit = host.hitTest(NSPoint(x: 100, y: 100)).map { String(describing: type(of: $0)) } ?? "nil"
        let verdict = clicks > 0 ? "click REACHES the button" : "click BLOCKED"
        let name = "\(label), \(style.rawValue)".padding(toLength: 58, withPad: " ", startingAt: 0)
        print("\(name) \(verdict) (actions \(clicks); AppKit hit view \(hit))")
        window.orderOut(nil)
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.finishLaunching()
            print("onScreen=\(onScreen) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            Task { @MainActor in
                await run("none (control)", EmptyView())
                await run("Color.black.opacity(0.4)", Color.black.opacity(0.4))
                await run(
                    "Color.black.opacity(0.4).allowsHitTesting(false)",
                    Color.black.opacity(0.4).allowsHitTesting(false))
                await run("Color.black.opacity(0.4).disabled(true)", Color.black.opacity(0.4).disabled(true))
                await run("Color.clear", Color.clear)
                await run("Color.black.opacity(0)", Color.black.opacity(0))
                await run("Color.black.opacity(0.001)", Color.black.opacity(0.001))
                await run("Rectangle().fill(.black).opacity(0)", Rectangle().fill(.black).opacity(0))
                await run("Text, glyph at the centre", Text("██████").font(.system(size: 40)))
                await run("Text, glyph at the centre, .opacity(0)", Text("██████").font(.system(size: 40)).opacity(0))
                await run("Text, space at the centre", Text("█" + String(repeating: " ", count: 30) + "█"))
                await run(
                    "Text(\"x\") off-centre in a 200 × 200 frame",
                    Text("x").offset(x: 60).frame(width: 200, height: 200))
                await run(
                    "scrim over the left half only",
                    Color.black.opacity(0.4).frame(width: 90).frame(maxWidth: .infinity, alignment: .leading))
                await run(
                    "scrim over the right half (the centre)",
                    Color.black.opacity(0.4).frame(width: 110).frame(maxWidth: .infinity, alignment: .trailing))
                // Not a layer: the button itself faded out, which
                // `AppearanceAndColors.md` says keeps its clickable regions.
                await run("no layer, the button at .opacity(0)", EmptyView(), buttonOpacity: 0)
                exit(0)
            }
            NSApp.run()
        }
    }
}
