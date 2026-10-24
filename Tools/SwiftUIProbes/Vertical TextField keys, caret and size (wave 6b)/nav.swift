import SwiftUI
import AppKit

// Measures caret motion in a vertical TextField: Up/Down across hard and soft
// lines and off either end, Ctrl-A/E/K/P/N, Home/End, typed-in multi-line text.

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
            @MainActor func set(_ t: String, _ caret: Int) { model.text = t; spin(); editor().setSelectedRange(NSRange(location: caret, length: 0)); spin(0.05) }
            @MainActor func key(_ chars: String, _ ign: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
                let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: ign, isARepeat: false, keyCode: code)!
                w.sendEvent(ev); spin(0.05)
            }
            let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
            @MainActor func caret() -> String { let r = editor().selectedRange(); return "\(r.location)+\(r.length)" }
            @MainActor func lines() -> String {
                let tv = editor(); guard let lm = tv.layoutManager else { return "?" }
                var out: [String] = []; var idx = 0
                let ns = tv.string as NSString
                while idx < lm.numberOfGlyphs {
                    var r = NSRange()
                    lm.lineFragmentRect(forGlyphAt: idx, effectiveRange: &r)
                    out.append(ns.substring(with: lm.characterRange(forGlyphRange: r, actualGlyphRange: nil)).debugDescription)
                    idx = NSMaxRange(r)
                }
                return out.joined(separator: " | ")
            }
            set("ab\ncd\nef", 0); key(up, up, 126, [.numericPad, .function]); print("hard: at 0, Up ->", caret())
            set("ab\ncd\nef", 1); key(down, down, 125, [.numericPad, .function]); print("hard: at 1, Down ->", caret())
            set("ab\ncd\nef", 7); key(down, down, 125, [.numericPad, .function]); print("hard: at 7, Down ->", caret())
            set("ab\ncd\nef", 8); key(up, up, 126, [.numericPad, .function]); print("hard: at 8, Up ->", caret())
            set("ab\ncd\nef", 1); key(up, up, 126, [.numericPad, .function]); print("hard: at 1, Up ->", caret())
            set("ab\ncd\nef", 4); key("\u{1}", "a", 0, [.control]); print("hard: at 4, Ctrl-A ->", caret())
            set("ab\ncd\nef", 4); key("\u{5}", "e", 14, [.control]); print("hard: at 4, Ctrl-E ->", caret())
            set("ab\ncd\nef", 4); key("\u{b}", "k", 40, [.control]); print("hard: at 4, Ctrl-K ->", model.text.debugDescription, caret())
            set("ab\ncd\nef", 5); key("\u{b}", "k", 40, [.control]); print("hard: at 5, Ctrl-K ->", model.text.debugDescription, caret())
            set("ab\ncd\nef", 4); key("\u{10}", "p", 35, [.control]); print("hard: at 4, Ctrl-P ->", caret())
            set("ab\ncd\nef", 4); key("\u{e}", "n", 45, [.control]); print("hard: at 4, Ctrl-N ->", caret())
            let soft = "aaa bbb ccc ddd eee fff ggg"
            set(soft, 0); print("soft lines:", lines())
            set(soft, soft.count); key(up, up, 126, [.numericPad, .function]); print("soft: at end, Up ->", caret())
            set(soft, 1); key(down, down, 125, [.numericPad, .function]); print("soft: at 1, Down ->", caret())
            set(soft, 5); key("\u{5}", "e", 14, [.control]); print("soft: at 5, Ctrl-E ->", caret())
            set(soft, 5); key("\u{1}", "a", 0, [.control]); print("soft: at 5, Ctrl-A ->", caret())
            let unbroken = String(repeating: "x", count: 40)
            set(unbroken, 0); print("unbroken lines:", lines())
            let spaces = "aaaa      bbbb"
            set(spaces, 0); print("spaces lines:", lines())
            set("", 0); editor().insertText("x\ny", replacementRange: NSRange(location: 0, length: 0)); spin(); print("insertText x\\ny ->", model.text.debugDescription)
            let home = String(UnicodeScalar(NSHomeFunctionKey)!)
            set("ab\ncd", 4); key(home, home, 115, [.function]); print("Home at 4 ->", caret())
            let pgdn = String(UnicodeScalar(NSPageDownFunctionKey)!)
            set("ab\ncd", 1); key(pgdn, pgdn, 121, [.function]); print("PageDown at 1 ->", caret())
        }
    }
}
