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
            let soft = "aaa bbb ccc ddd eee fff ggg"
            model.text = soft; spin()
            editor().setSelectedRange(NSRange(location: 12, length: 0)); spin(0.05)
            report("set 12")
            editor().setSelectedRange(NSRange(location: 11, length: 0)); spin(0.05)
            key(String(UnicodeScalar(NSRightArrowFunctionKey)!), String(UnicodeScalar(NSRightArrowFunctionKey)!), 124, [.numericPad, .function])
            report("Right from 11")
            editor().setSelectedRange(NSRange(location: 13, length: 0)); spin(0.05)
            key(String(UnicodeScalar(NSLeftArrowFunctionKey)!), String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123, [.numericPad, .function])
            report("Left from 13")
            editor().setSelectedRange(NSRange(location: 5, length: 0)); spin(0.05)
            key("\u{5}", "e", 14, [.control])
            report("Ctrl-E from 5")
            // Typing up to the wrap: start from "aaa bbb ccc" and type " ".
            model.text = "aaa bbb ccc"; spin()
            editor().setSelectedRange(NSRange(location: 11, length: 0)); spin(0.05)
            key(" ", " ", 49)
            report("typed space at 11")
            key("d", "d", 2)
            report("typed d")
        }
    }
}
