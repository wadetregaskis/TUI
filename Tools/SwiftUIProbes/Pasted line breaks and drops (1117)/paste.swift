import AppKit
import ObjectiveC
import SwiftUI

// What a SwiftUI text field keeps of a pasted line break, tab or Unicode
// line/paragraph separator (bug hunt 1117, 2026-11-17), and whether a field
// or a TextEditor takes a dropped string with no modifier held.
//
// Paste: each field is focused, its contents selected, and ⌘V's action
// (`paste:`) is sent down the responder chain as the Edit menu sends it, so
// the field editor SwiftUI installed does the paste. `NSPasteboard.general`
// is replaced, for this process only, by a pasteboard of its own name, so
// the probe never reads or writes the real clipboard. After the paste the
// probe prints the bound text (escaped, with its scalars), whether onSubmit
// ran, and the bound text again once the field has lost focus.
//
// Drop: a string is offered to the view under the field's centre that is
// registered for it, through an NSDraggingInfo of the probe's own, with the
// operations an unmodified drag from another app offers (copy, generic,
// move), and with the field NOT focused. The probe prints the operation
// draggingEntered chose, whether performDragOperation took it, and the bound
// text after. AppKit's own drag loop is not run (it needs a real mouse), so
// this is the destination's half of a drop only.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 paste.swift -o "$TMPDIR/paste"
//   "$TMPDIR/paste"

@MainActor final class Model: ObservableObject {
    @Published var text = ""
    @Published var submits = 0
}

enum Kind: String, CaseIterable { case plain, vertical, secure, editor }

struct Probe: View {
    let kind: Kind
    @ObservedObject var m: Model
    @State private var other = ""
    var body: some View {
        VStack {
            switch kind {
            case .plain: TextField("Field", text: $m.text).onSubmit { m.submits += 1 }
            case .vertical: TextField("Field", text: $m.text, axis: .vertical).onSubmit { m.submits += 1 }
            case .secure: SecureField("Field", text: $m.text).onSubmit { m.submits += 1 }
            case .editor: TextEditor(text: $m.text).frame(height: 60)
            }
            TextField("Other", text: $other)
        }
        .frame(width: 220)
        .padding()
    }
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func views(_ v: NSView) -> [NSView] {
    var out: [NSView] = []
    if v is NSTextField || v is NSTextView { out.append(v) }
    for c in v.subviews { out += views(c) }
    return out
}

func escaped(_ s: String) -> String {
    s.unicodeScalars.map { scalar -> String in
        switch scalar {
        case "\n": "\\n"
        case "\r": "\\r"
        case "\t": "\\t"
        case "\\": "\\\\"
        case "\"": "\\\""
        default:
            scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || scalar.value > 0x7E
                ? "\\u{\(String(scalar.value, radix: 16, uppercase: true))}" : String(scalar)
        }
    }.joined()
}

/// How the field editor laid the pasted text out: its line fragments, and
/// where the last character's glyph sits against the first's.
@MainActor func lines(_ editor: NSTextView) -> String {
    guard let manager = editor.layoutManager, let container = editor.textContainer else { return "no layout manager" }
    manager.ensureLayout(for: container)
    let glyphs = manager.numberOfGlyphs
    var fragments = 0
    var index = 0
    while index < glyphs {
        var range = NSRange()
        manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
        fragments += 1
        index = NSMaxRange(range)
    }
    guard glyphs > 0 else { return "no glyphs" }
    let first = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).origin.y
    let last = manager.lineFragmentRect(forGlyphAt: glyphs - 1, effectiveRange: nil).origin.y
    let x = manager.location(forGlyphAt: glyphs - 1).x
    return "\(fragments) line fragment(s), last glyph's line at y \(Int(last - first)), x \(Int(x)); "
        + "wraps \(container.widthTracksTextView), single line \((editor.window?.firstResponder as? NSTextView)?.isFieldEditor ?? false)"
}

/// What `view` draws, in points: the runs of columns that hold ink (a run per
/// stretch of glyphs, so "ab cd" reads as two runs and "ab" as one), and the
/// rows the ink spans against the view's height, so a second line shows.
@MainActor func ink(_ view: NSView) -> String {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return "no bitmap" }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    var runs: [String] = []
    var start: Int?
    var top = Int.max, bottom = -1
    let rows = Int(bitmap.pixelsHigh), columns = Int(bitmap.pixelsWide)
    let scale = Double(columns) / view.bounds.width
    for x in 0...columns {
        var inked = false
        if x < columns {
            for y in 0..<rows {
                if let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   colour.alphaComponent > 0.5, colour.brightnessComponent < 0.5 {
                    inked = true
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
        }
        if inked, start == nil { start = x }
        if !inked, let first = start {
            runs.append("\(Int(Double(first) / scale))-\(Int(Double(x) / scale))")
            start = nil
        }
    }
    guard !runs.isEmpty else { return "no ink" }
    return runs.joined(separator: " ")
        + ", rows \(Int(Double(top) / scale))-\(Int(Double(bottom + 1) / scale)) of \(Int(view.bounds.height))"
}

let probePasteboard = NSPasteboard.withUniqueName()

/// Replaces `+[NSPasteboard generalPasteboard]` with one returning the probe's
/// own pasteboard, so `paste:` reads it and the user's clipboard is untouched.
func redirectGeneralPasteboard() {
    let metaclass: AnyClass = object_getClass(NSPasteboard.self)!
    let method = class_getClassMethod(NSPasteboard.self, #selector(getter: NSPasteboard.general))!
    let block: @convention(block) (AnyObject) -> NSPasteboard = { _ in probePasteboard }
    method_setImplementation(method, imp_implementationWithBlock(block))
    _ = metaclass
    precondition(NSPasteboard.general === probePasteboard, "redirect failed")
}

let pastes: [(String, String)] = [
    ("LF", "ab\ncd"), ("CRLF", "ab\r\ncd"), ("CR", "ab\rcd"), ("tab", "ab\tcd"),
    ("U+2028", "ab\u{2028}cd"), ("U+2029", "ab\u{2029}cd"), ("trailing LF", "abcd\n"),
    ("U+0085", "ab\u{85}cd"), ("ESC", "ab\u{1B}cd"),
    // References for the ink columns: the first word, the second, one line, two words.
    ("ref", "ab"), ("ref", "cd"), ("ref", "abcd"), ("ref", "ab cd"),
]

@MainActor func window(for kind: Kind, model: Model) -> (NSWindow, NSView, NSView) {
    let hosting = NSHostingView(rootView: Probe(kind: kind, m: model))
    let size = CGSize(width: 260, height: 180)
    hosting.frame = NSRect(origin: .zero, size: size)
    let w = KeyWindow(
        contentRect: NSRect(origin: CGPoint(x: 100, y: 100), size: size), styleMask: [.titled],
        backing: .buffered, defer: false)
    w.contentView = hosting
    w.makeKeyAndOrderFront(nil)
    spin(0.5)
    let found = views(hosting)
    return (w, found[0], found.last!)
}

@MainActor func paste(_ kind: Kind) {
    let model = Model()
    let (w, field, other) = window(for: kind, model: model)
    print("\(kind.rawValue): \(type(of: field)), key window \(w.isKeyWindow), app active \(NSApp.isActive)")
    for (name, string) in pastes {
        model.text = ""
        spin(0.1)
        w.makeFirstResponder(field)
        spin(0.1)
        _ = w.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
        probePasteboard.clearContents()
        probePasteboard.setString(string, forType: .string)
        let before = model.submits
        let responder = w.firstResponder.map { "\(type(of: $0))" } ?? "nil"
        let sent = w.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: nil) ?? false
        spin()
        let bound = model.text
        let submitted = model.submits - before
        let layout = (w.firstResponder as? NSTextView).map(lines) ?? "no field editor"
        w.makeFirstResponder(other)
        spin()
        print("  \(name.padding(toLength: 11, withPad: " ", startingAt: 0)) \"\(escaped(string))\" -> "
            + "\"\(escaped(bound))\" submits +\(submitted), after focus leaves \"\(escaped(model.text))\""
            + (sent ? "" : " (paste: not sent)") + " [\(responder)]")
        print("              editor layout: \(layout); unfocused field's ink columns \(ink(field))")
    }
    w.orderOut(nil)
}

final class Drag: NSObject, NSDraggingInfo {
    let window: NSWindow
    let location: NSPoint
    init(window: NSWindow, location: NSPoint) {
        self.window = window
        self.location = location
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic, .move] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { probePasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor func drop(_ kind: Kind, focused: Bool) {
    let model = Model()
    model.text = "xy"
    let (w, field, other) = window(for: kind, model: model)
    w.makeFirstResponder(focused ? field : other)
    spin()
    let label = "\(kind.rawValue) drop, field \(focused ? "focused" : "not focused")"
    let centre = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
    var target = w.contentView!.hitTest(w.contentView!.superview!.convert(centre, from: nil))
    let legacyString = NSPasteboard.PasteboardType("NSStringPboardType")
    while let view = target, !view.registeredDraggedTypes.contains(.string), !view.registeredDraggedTypes.contains(legacyString) { target = view.superview }
    let types = field.registeredDraggedTypes.map(\.rawValue).filter { $0 == "NSStringPboardType" || $0 == NSPasteboard.PasteboardType.string.rawValue }
    guard let view = target else {
        print("\(label): no view under the field is registered for strings; field registers \(types)")
        w.orderOut(nil)
        return
    }
    probePasteboard.clearContents()
    probePasteboard.setString("DROP", forType: .string)
    let info = Drag(window: w, location: centre)
    let entered = view.draggingEntered(info)
    let updated = view.draggingUpdated(info)
    var performed = false
    if !updated.isEmpty || !entered.isEmpty {
        let prepared = view.prepareForDragOperation(info)
        performed = prepared && view.performDragOperation(info)
        view.concludeDragOperation(info)
    } else {
        view.draggingExited(info)
    }
    spin(0.4)
    print("\(label), on \(type(of: view)) (field \(type(of: field)), field registers \(types.count) text types): "
        + "entered \(entered.rawValue), updated \(updated.rawValue), performed \(performed), bound \"\(escaped(model.text))\", "
        + "first responder \(w.firstResponder.map { "\(type(of: $0))" } ?? "nil")")
    w.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            NSApp.activate(ignoringOtherApps: true)
            redirectGeneralPasteboard()
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            for kind in Kind.allCases { paste(kind) }
            for kind in Kind.allCases { drop(kind, focused: false); drop(kind, focused: true) }
            probePasteboard.releaseGlobally()
        }
    }
}
