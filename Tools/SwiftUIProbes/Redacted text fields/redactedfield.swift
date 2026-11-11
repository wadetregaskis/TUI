import AppKit
import SwiftUI

// What SwiftUI does with a TextField under redaction (the owner's hidden-text
// ruling, 2026-11-10): whether the AppKit field behind it still holds and draws
// the real text, takes the focus, and moves by words. Compared with a plain
// field and a SecureField. macOS 15, offscreen. Never touches the pasteboard.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> (NSWindow, NSHostingView<V>) {
    let size = CGSize(width: 300, height: 60)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.titled],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func fields(in view: NSView) -> [NSTextField] {
    ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { fields(in: $0) }
}
@MainActor func pixels(_ view: NSView) -> [UInt8] {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerPlane))
}

let value = "hunter2 abc"
enum Case: String, CaseIterable { case plain, placeholder, privacy, privacyUnmarked, secure, text, textPlaceholder }

@MainActor func view(_ c: Case) -> AnyView {
    let binding = Binding.constant(value)
    switch c {
    case .plain: return AnyView(TextField("Prompt", text: binding))
    case .placeholder: return AnyView(TextField("Prompt", text: binding).redacted(reason: .placeholder))
    case .privacy: return AnyView(TextField("Prompt", text: binding).privacySensitive().redacted(reason: .privacy))
    case .privacyUnmarked: return AnyView(TextField("Prompt", text: binding).redacted(reason: .privacy))
    case .secure: return AnyView(SecureField("Prompt", text: binding))
    // The check that this harness draws redaction at all: a Text, plain and redacted.
    case .text: return AnyView(Text(value))
    case .textPlaceholder: return AnyView(Text(value).redacted(reason: .placeholder))
    }
}

@MainActor func run() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var plainPixels: [UInt8] = []
    for c in Case.allCases {
        let (window, hosting) = host(view(c).padding())
        spin()
        let found = fields(in: hosting)
        let drawn = pixels(hosting)
        if c == .plain || c == .text { plainPixels = drawn }
        let differing = zip(drawn, plainPixels).filter { $0 != $1 }.count
        print("== \(c.rawValue): \(found.count) field(s); bytes differing from plain (a Text's: from the plain Text): \(differing)")
        for field in found {
            print("  \(type(of: field)) string=\(field.stringValue.debugDescription) editable=\(field.isEditable) selectable=\(field.isSelectable) hidden=\(field.isHidden) alpha=\(field.alphaValue)")
            let took = window.makeFirstResponder(field)
            spin(0.2)
            guard took, let editor = field.currentEditor() as? NSTextView else {
                print("  first responder: \(took), no field editor")
                continue
            }
            editor.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
            editor.moveWordBackward(nil)
            print("  first responder: true; moveWordBackward from the end -> \(editor.selectedRange().location)")
            let word = editor.selectionRange(
                forProposedRange: NSRange(location: 2, length: 0), granularity: .selectByWord)
            print("  word around 2 -> \(word.location)..<\(word.location + word.length)")
        }
        fflush(stdout)
    }
}

MainActor.assumeIsolated { run() }
