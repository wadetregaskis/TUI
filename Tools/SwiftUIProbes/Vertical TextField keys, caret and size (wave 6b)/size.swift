import SwiftUI
import AppKit

// Measures how a vertical TextField sizes: growth with wrapped text, under
// each lineLimit form, and with a long prompt.

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func height<V: View>(_ v: V) -> CGFloat {
    let h = NSHostingView(rootView: v.frame(width: 120).fixedSize(horizontal: false, vertical: true))
    h.frame = NSRect(x: 0, y: 0, width: 120, height: 400)
    let w = KeyWindow(contentRect: NSRect(x: -3000, y: -3000, width: 120, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    spin(0.2)
    return h.fittingSize.height
}

let short = "word"
let long = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen"
let unbroken = String(repeating: "x", count: 80)

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            @MainActor func row(_ label: String, _ v: some View) { print(label.padding(toLength: 40, withPad: " ", startingAt: 0), height(v)) }
            row("plain empty", TextField("T", text: .constant("")))
            row("plain long", TextField("T", text: .constant(long)))
            row("vertical empty", TextField("T", text: .constant(""), axis: .vertical))
            row("vertical short", TextField("T", text: .constant(short), axis: .vertical))
            row("vertical a\\nb", TextField("T", text: .constant("a\nb"), axis: .vertical))
            row("vertical a\\nb\\nc", TextField("T", text: .constant("a\nb\nc"), axis: .vertical))
            row("vertical long", TextField("T", text: .constant(long), axis: .vertical))
            row("vertical unbroken", TextField("T", text: .constant(unbroken), axis: .vertical))
            row("vertical long lineLimit(2)", TextField("T", text: .constant(long), axis: .vertical).lineLimit(2))
            row("vertical short lineLimit(3,res)", TextField("T", text: .constant(short), axis: .vertical).lineLimit(3, reservesSpace: true))
            row("vertical short lineLimit(2...4)", TextField("T", text: .constant(short), axis: .vertical).lineLimit(2...4))
            row("vertical long lineLimit(2...4)", TextField("T", text: .constant(long), axis: .vertical).lineLimit(2...4))
            row("vertical short lineLimit(3...)", TextField("T", text: .constant(short), axis: .vertical).lineLimit(3...))
            row("vertical long lineLimit(...2)", TextField("T", text: .constant(long), axis: .vertical).lineLimit(...2))
            row("vertical empty long prompt", TextField("T", text: .constant(""), prompt: Text(long), axis: .vertical))
            row("vertical empty a\\nb prompt", TextField("T", text: .constant(""), prompt: Text("a\nb"), axis: .vertical))
            row("horizontal long", TextField("T", text: .constant(long), axis: .horizontal))
            row("horizontal a\\nb", TextField("T", text: .constant("a\nb"), axis: .horizontal))
            row("plain a\\nb", TextField("T", text: .constant("a\nb")))
            row("plain lineLimit(3) long", TextField("T", text: .constant(long)).lineLimit(3))
            row("Text long", Text(long))
            row("Text one line", Text(short))
        }
    }
}
