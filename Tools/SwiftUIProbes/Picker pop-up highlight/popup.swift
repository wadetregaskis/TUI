import AppKit
import SwiftUI

// PICKER-POINTER-OPEN: when a pop-up button's menu is opened by the pointer,
// which item does macOS highlight — the current value, or none? A `.menu`
// Picker's NSPopUpButton is clicked (`performClick`, a simulated click), and
// a timer in the menu's tracking loop reads its highlighted item twice, then
// ends the tracking. (A raw mouse-down sent to the window waits for its
// mouse-up in the tracking loop, so it is not used.)

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor final class Model: ObservableObject { @Published var choice = "Banana" }
struct Probe: View {
    @ObservedObject var model: Model
    var body: some View {
        Picker("Fruit", selection: $model.choice) {
            ForEach(["Apple", "Banana", "Cherry"], id: \.self) { Text($0) }
        }
        .pickerStyle(.menu).frame(width: 200).padding()
    }
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func popups(_ v: NSView) -> [NSPopUpButton] { (v as? NSPopUpButton).map { [$0] } ?? v.subviews.flatMap(popups) }

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let model = Model()
            let h = NSHostingView(rootView: Probe(model: model))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
            let w = KeyWindow(contentRect: NSRect(x: 200, y: 300, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = h; w.makeKeyAndOrderFront(nil); spin(0.5)
            guard let popup = popups(h).first, let menu = popup.menu else { print("no NSPopUpButton"); exit(1) }
            print("popup class", type(of: popup), "selected", popup.titleOfSelectedItem ?? "nil")
            // Read the highlight from inside the menu's tracking loop, then end it.
            var samples: [String] = []
            let timer = Timer(timeInterval: 0.3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    samples.append(menu.highlightedItem?.title ?? "none")
                    if samples.count >= 2 { menu.cancelTracking() }
                }
            }
            RunLoop.main.add(timer, forMode: .eventTracking)
            popup.performClick(nil)
            timer.invalidate()
            print("performClick highlight samples", samples)
            exit(0)
        }
    }
}
