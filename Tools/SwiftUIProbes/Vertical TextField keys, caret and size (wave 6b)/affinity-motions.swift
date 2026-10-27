import SwiftUI
import AppKit

// Where a vertical TextField draws its insertion point at an offset where a
// row wrapped: on the earlier row (upstream) or the later (downstream), and
// what the field editor's selectionAffinity says, after a click-like set, an
// arrow key, typing, and End.

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor final class Model: ObservableObject { @Published var text = "" }
struct Probe: View {
    @ObservedObject var model: Model
    var body: some View { TextField("T", text: $model.text, axis: .vertical).frame(width: 90).padding() }
}
@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.12) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func fields(_ v: NSView) -> [NSView] { (v is NSTextField ? [v] : []) + v.subviews.flatMap(fields) }

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let model = Model()
            let h = NSHostingView(rootView: Probe(model: model))
            h.frame = NSRect(x: 0, y: 0, width: 200, height: 300)
            let w = KeyWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = h; w.makeKeyAndOrderFront(nil); keep.append(w); spin(0.4)
            let field = fields(h).first!
            w.makeFirstResponder(field); spin()
            @MainActor func editor() -> NSTextView { w.firstResponder as! NSTextView }
            @MainActor func key(_ chars: String, _ ign: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
                let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: ign, isARepeat: false, keyCode: code)!
                w.sendEvent(ev); spin(0.05)
            }
            @MainActor func report(_ label: String) {
                let tv = editor()
                let r = tv.selectedRange()
                var rect = NSRect.zero
                if let lm = tv.layoutManager, let tc = tv.textContainer {
                    let glyph = lm.glyphIndexForCharacter(at: min(r.location, (tv.string as NSString).length))
                    _ = tc
                    rect = lm.lineFragmentRect(forGlyphAt: min(glyph, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
                }
                let caretRect = tv.firstRect(forCharacterRange: NSRange(location: r.location, length: 0), actualRange: nil)
                print(label.padding(toLength: 28, withPad: " ", startingAt: 0), "caret \(r.location)+\(r.length)", "affinity", tv.selectionAffinity == .upstream ? "upstream" : "downstream", "caretRect.y", caretRect.origin.y, "x", caretRect.origin.x, "fragment.y", rect.origin.y)
            }
            // The motions affinity.swift left unmeasured (D4X-FULLER): deletion,
            // Up and Down, and the line commands (⌘← / ⌘→), each landing on
            // offset 12, where the first row wraps ("aaa bbb ccc " | "ddd ...").
            let soft = "aaa bbb ccc ddd eee fff ggg hhh iii jjj"
            @MainActor func reset(_ at: Int) { model.text = soft; spin(); editor().setSelectedRange(NSRange(location: at, length: 0)); spin(0.05) }
            let right = String(UnicodeScalar(NSRightArrowFunctionKey)!), left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
            let fwdDel = String(UnicodeScalar(NSDeleteFunctionKey)!)
            reset(12); report("set 12 (baseline)")
            reset(13); key("\u{7f}", "\u{7f}", 51); report("Backspace from 13")
            reset(12); key(fwdDel, fwdDel, 117, [.function]); report("Forward Delete at 12")
            reset(0); key(down, down, 125, [.numericPad, .function]); report("Down from 0")
            reset(24); key(up, up, 126, [.numericPad, .function]); report("Up from 24")
            reset(14); key(left, left, 123, [.numericPad, .function, .command]); report("Cmd-Left from 14")
            reset(5); key(right, right, 124, [.numericPad, .function, .command]); report("Cmd-Right from 5")
            reset(14); key("\u{1}", "a", 0, [.control]); report("Ctrl-A from 14")
            reset(5); key("\u{5}", "e", 14, [.control]); report("Ctrl-E from 5")
            reset(11); key(right, right, 124, [.numericPad, .function]); report("Right from 11")
            reset(12); key(right, right, 124, [.numericPad, .function, .option]); report("Opt-Right from 8 (word)")
            // Deletion from a downstream caret: does it keep the lean or set one?
            reset(14); key(left, left, 123, [.numericPad, .function, .command]); key(fwdDel, fwdDel, 117, [.function])
            report("Cmd-Left, then Fwd Delete")
            reset(14); key(left, left, 123, [.numericPad, .function, .command]); key(right, right, 124, [.numericPad, .function])
            key("\u{7f}", "\u{7f}", 51); report("Cmd-Left, Right, Backspace")
            reset(15); key("\u{7f}", "\u{7f}", 51); key("\u{7f}", "\u{7f}", 51); key("\u{7f}", "\u{7f}", 51)
            report("Backspace x3 from 15")
            reset(12); key(right, right, 124, [.numericPad, .function, .command]); report("Cmd-Right at 12 (upstream)")
            exit(0)
        }
    }
}
