// O-28 probe: what macOS text views do with the selection when the APP replaces or edits the text.
//
// Part 1: NSTextView (TextKit 1 and TextKit 2), selection {2,5} ("cdefg") of "abcdefghij", then
//         a whole-string assignment or a textStorage edit; selectedRange read back.
// Part 1b: NSTextView, edits that meet the selection (or a caret) at an edge.
// Part 2: NSTextField with its field editor active and a selection, then `stringValue = ...`.
// Part 3: SwiftUI TextEditor(text:) / TextField(text:), focused, selection made through the
//         underlying NSTextView / field editor, then the @State the binding reads is set.
// Part 4: TextEditor(text:selection:) / TextField(text:selection:) (macOS 15): the app writes the
//         text, the selection, or both; NSTextView's selection and the binding are read back.
// Part 5: macOS 26 API (AttributedTextSelection, transform(updating:)): compile check; runs only
//         on a macOS 26 runtime.
//
// Every case gets a fresh view in its own offscreen titled NSWindow (titled, so it can hold a
// first responder); the run loop spins after each step.
//
// Build: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 6 \
//          -parse-as-library probe.swift -o probe && ./probe
//        PROBE_EDGES=1 ./probe > probe-edges.out      # Part 1b alone
import AppKit
import SwiftUI

let original = "abcdefghij"
let startSel = NSRange(location: 2, length: 5)        // "cdefg"

@MainActor var keep: [NSWindow] = []
@MainActor func window(_ content: NSView) -> NSWindow {
    let size = CGSize(width: 400, height: 200)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    content.frame = NSRect(origin: .zero, size: size)
    w.contentView = content
    w.orderFrontRegardless()
    keep.append(w)
    content.layoutSubtreeIfNeeded()
    return w
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func r(_ n: NSRange) -> String { n.location == NSNotFound ? "{NotFound}" : "{\(n.location),\(n.length)}" }
func show(_ s: String) -> String { "\"\(s)\"" }

@MainActor func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
    if let t = v as? T { return t }
    for s in v.subviews { if let t = find(type, in: s) { return t } }
    return nil
}

// MARK: - Part 1: NSTextView

@MainActor func part1() {
    print("## Part 1: NSTextView, selection \(r(startSel)) of \(show(original))\n")
    typealias Edit = (String, (NSTextView) -> Void)
    let edits: [Edit] = [
        ("(a) textView.string = \"0123456789\" (same length)", { $0.string = "0123456789" }),
        ("(a') textView.string = \"0123\" (shorter than the selection's end)", { $0.string = "0123" }),
        ("(a'') textView.string = \"0123456789ABCDEF\" (longer)", { $0.string = "0123456789ABCDEF" }),
        ("(b) textStorage.replaceCharacters({0,0}, \"XY\") (insert before)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 0), with: "XY") }),
        ("(b') textStorage.replaceCharacters({1,0}, \"XY\") (insert just before)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 1, length: 0), with: "XY") }),
        ("(c) textStorage.replaceCharacters({3,2}, \"Z\") (inside, shrinks)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 3, length: 2), with: "Z") }),
        ("(c') textStorage.replaceCharacters({3,2}, \"ZZZZ\") (inside, grows)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 3, length: 2), with: "ZZZZ") }),
        ("(c'') textStorage.replaceCharacters({1,3}, \"Q\") (straddles the start)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 1, length: 3), with: "Q") }),
        ("(c''') textStorage.replaceCharacters({6,3}, \"Q\") (straddles the end)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 6, length: 3), with: "Q") }),
        ("(d) textStorage.replaceCharacters({10,0}, \"XYZ\") (append)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 10, length: 0), with: "XYZ") }),
        ("(e) textStorage.replaceCharacters({0,10}, \"0123456789ABCDEF\") (whole, longer)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 10), with: "0123456789ABCDEF") }),
        ("(e') textStorage.replaceCharacters({0,10}, \"012\") (whole, shorter)", { $0.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 10), with: "012") }),
        ("(e'') textStorage.setAttributedString(\"0123456789\")", { $0.textStorage!.setAttributedString(NSAttributedString(string: "0123456789")) }),
        ("(f) textView.replaceCharacters({0,0}, \"XY\") (NSText API)", { $0.replaceCharacters(in: NSRange(location: 0, length: 0), with: "XY") }),
        ("(g) textView.insertText(\"XY\", replacementRange: {0,0})", { $0.insertText("XY", replacementRange: NSRange(location: 0, length: 0)) }),
    ]
    print("| edit | TextKit 1: text after | TextKit 1: selectedRange | TextKit 2: selectedRange |")
    print("|---|---|---|---|")
    for (label, edit) in edits {
        var cols: [String] = []
        var text = ""
        for tk2 in [false, true] {
            let tv = NSTextView(usingTextLayoutManager: tk2)
            tv.string = original
            let w = window(tv)
            w.makeFirstResponder(tv)
            tv.setSelectedRange(startSel)
            spin(0.05)
            edit(tv)
            spin(0.1)
            if !tk2 { text = tv.string }
            cols.append(r(tv.selectedRange()))
            precondition(tk2 == (tv.textLayoutManager != nil))
        }
        print("| \(label) | \(show(text)) | \(cols[0]) | \(cols[1]) |")
    }
    print()
}

// MARK: - Part 1b: NSTextView, edits that meet the selection at an edge

/// An edit that ends where the selection starts, or starts where it ends, or
/// meets a caret: Part 1's rows leave these open (added for O-28 (a), 2026-11-23).
@MainActor func part1b() {
    print("## Part 1b: NSTextView, edits at the selection's edges, in \(show(original))\n")
    typealias Edge = (String, NSRange, NSRange, String)
    let edges: [Edge] = [
        ("insert at the selection's start", startSel, NSRange(location: 2, length: 0), "XY"),
        ("insert at the selection's end", startSel, NSRange(location: 7, length: 0), "XY"),
        ("replace ending at the start", startSel, NSRange(location: 0, length: 2), "Q"),
        ("replace starting at the end", startSel, NSRange(location: 7, length: 2), "Q"),
        ("delete ending at the start", startSel, NSRange(location: 0, length: 2), ""),
        ("delete starting at the end", startSel, NSRange(location: 7, length: 2), ""),
        ("delete inside", startSel, NSRange(location: 3, length: 2), ""),
        ("insert inside", startSel, NSRange(location: 4, length: 0), "XY"),
        ("delete the selection exactly", startSel, NSRange(location: 2, length: 5), ""),
        ("insert at a caret", NSRange(location: 5, length: 0), NSRange(location: 5, length: 0), "XY"),
        ("replace starting at a caret", NSRange(location: 5, length: 0), NSRange(location: 5, length: 2), "Q"),
        ("replace ending at a caret", NSRange(location: 5, length: 0), NSRange(location: 3, length: 2), "Q"),
        ("replace across a caret", NSRange(location: 5, length: 0), NSRange(location: 4, length: 2), "Q"),
        ("append at a caret at the end", NSRange(location: 10, length: 0), NSRange(location: 10, length: 0), "XY"),
        ("insert at 0, caret at 0", NSRange(location: 0, length: 0), NSRange(location: 0, length: 0), "XY"),
    ]
    print("| edit | selection before | replaced | with | text after | TextKit 1 | TextKit 2 |")
    print("|---|---|---|---|---|---|---|")
    for (label, selection, range, replacement) in edges {
        var cols: [String] = []
        var text = ""
        for tk2 in [false, true] {
            let tv = NSTextView(usingTextLayoutManager: tk2)
            tv.string = original
            let w = window(tv)
            w.makeFirstResponder(tv)
            tv.setSelectedRange(selection)
            spin(0.05)
            tv.textStorage!.replaceCharacters(in: range, with: replacement)
            spin(0.1)
            if !tk2 { text = tv.string }
            cols.append(r(tv.selectedRange()))
        }
        print("| \(label) | \(r(selection)) | \(r(range)) | \(show(replacement)) | \(show(text)) | \(cols[0]) | \(cols[1]) |")
    }
    print()
}

// MARK: - Part 2: NSTextField with an active field editor

@MainActor func part2() {
    print("## Part 2: NSTextField, field editor active, selection \(r(startSel)) of \(show(original))\n")
    print("| assignment | editor still current | editor text | editor selectedRange |")
    print("|---|---|---|---|")
    for new in ["0123456789", original + "XYZ", "XY" + original, "012"] {
        let f = NSTextField(string: original)
        let box = NSView()
        box.addSubview(f)
        let w = window(box)
        f.frame = NSRect(x: 10, y: 10, width: 300, height: 24)
        w.makeFirstResponder(f)
        guard let ed = f.currentEditor() as? NSTextView else { print("| \(show(new)) | no field editor | | |"); continue }
        ed.setSelectedRange(startSel)
        spin(0.05)
        f.stringValue = new
        spin(0.1)
        let ed2 = f.currentEditor() as? NSTextView
        print("| stringValue = \(show(new)) | \(ed2 === ed ? "yes" : (ed2 == nil ? "no (ended)" : "a different one")) | \(show(ed2?.string ?? "-")) | \(ed2.map { r($0.selectedRange()) } ?? "-") |")
    }
    print()
}

// MARK: - Part 3: SwiftUI TextEditor(text:) / TextField(text:)

@MainActor final class Rig {
    var setText: ((String) -> Void)?
    var getText: (() -> String)?
    var setSel: ((TextSelection?) -> Void)?
    var getSel: (() -> TextSelection?)?
    var setBoth: ((String, TextSelection?) -> Void)?
}

struct PlainEditor: View {
    let rig: Rig
    @State var text = original
    var body: some View {
        let _ = { rig.setText = { text = $0 }; rig.getText = { text } }()
        TextEditor(text: $text)
    }
}
struct PlainField: View {
    let rig: Rig
    @State var text = original
    var body: some View {
        let _ = { rig.setText = { text = $0 }; rig.getText = { text } }()
        TextField("f", text: $text).frame(width: 300)
    }
}

/// The focused NSTextView: TextEditor's own, or a TextField's field editor.
@MainActor func focus(_ h: NSView, field: Bool) -> NSTextView? {
    if field {
        guard let f = find(NSTextField.self, in: h) else { return nil }
        h.window?.makeFirstResponder(f)
        return f.currentEditor() as? NSTextView
    }
    guard let tv = find(NSTextView.self, in: h) else { return nil }
    h.window?.makeFirstResponder(tv)
    return tv
}
@MainActor func current(_ h: NSView, field: Bool) -> NSTextView? {
    field ? find(NSTextField.self, in: h)?.currentEditor() as? NSTextView : find(NSTextView.self, in: h)
}

@MainActor func part3() {
    print("## Part 3: SwiftUI TextEditor(text:) / TextField(text:), selection \(r(startSel)) set on the NSTextView, then @State set\n")
    print("| view | new @State text | view text after | selectedRange after |")
    print("|---|---|---|---|")
    for field in [false, true] {
        for new in ["0123456789", original + "XYZ", "XY" + original, "012", original] {
            let rig = Rig()
            let h: NSView = field ? NSHostingView(rootView: PlainField(rig: rig)) : NSHostingView(rootView: PlainEditor(rig: rig))
            _ = window(h)
            spin()
            guard let tv = focus(h, field: field) else { print("| \(field ? "TextField" : "TextEditor") | no text view found | | |"); continue }
            tv.setSelectedRange(startSel)
            spin(0.1)
            let before = r(tv.selectedRange())
            rig.setText?(new)
            spin(0.3); h.layoutSubtreeIfNeeded(); spin(0.1)
            let now = current(h, field: field)
            let label = new == original ? "\(show(new)) (unchanged)" : show(new)
            print("| \(field ? "TextField" : "TextEditor") (sel before \(before)) | \(label) | \(show(now?.string ?? "-")) | \(now.map { r($0.selectedRange()) } ?? "-") |")
        }
    }
    print()
}

// MARK: - Part 4: TextEditor(text:selection:) / TextField(text:selection:)

func describe(_ s: TextSelection?, in text: String) -> String {
    guard let s else { return "nil" }
    switch s.indices {
    case .selection(let rg):
        // A selection the app did not rewrite still holds the OLD string's indices; past the new end,
        // utf16Offset(in:) traps, so say so and give the old offsets (ASCII: same in either string).
        if rg.upperBound > text.endIndex {
            return "stale, past the end (\(rg.lowerBound.utf16Offset(in: original))..<\(rg.upperBound.utf16Offset(in: original)) of the old text)"
        }
        let lo = rg.lowerBound.utf16Offset(in: text), hi = rg.upperBound.utf16Offset(in: text)
        return s.isInsertion ? "insertion \(lo)" : "\(lo)..<\(hi)"
    case .multiSelection(let set):
        return "multi(\(set.ranges.map { "\($0.lowerBound.utf16Offset(in: text))..<\($0.upperBound.utf16Offset(in: text))" }.joined(separator: ",")))"
    @unknown default:
        return "unknown"
    }
}
func sel(_ text: String, _ lo: Int, _ hi: Int) -> TextSelection {
    TextSelection(range: text.index(text.startIndex, offsetBy: lo)..<text.index(text.startIndex, offsetBy: hi))
}

struct SelEditor: View {
    let rig: Rig
    @State var text = original
    @State var selection: TextSelection?
    var body: some View {
        let _ = { rig.setText = { text = $0 }; rig.getText = { text }
                  rig.setSel = { selection = $0 }; rig.getSel = { selection }
                  rig.setBoth = { text = $0; selection = $1 } }()
        TextEditor(text: $text, selection: $selection)
    }
}
struct SelField: View {
    let rig: Rig
    @State var text = original
    @State var selection: TextSelection?
    var body: some View {
        let _ = { rig.setText = { text = $0 }; rig.getText = { text }
                  rig.setSel = { selection = $0 }; rig.getSel = { selection }
                  rig.setBoth = { text = $0; selection = $1 } }()
        TextField("f", text: $text, selection: $selection).frame(width: 300)
    }
}

@MainActor func part4() {
    print("## Part 4: TextEditor(text:selection:) / TextField(text:selection:) (macOS 15 API)\n")
    print("| view | step | view text | view selectedRange | binding text | binding selection |")
    print("|---|---|---|---|---|---|")
    let inserted = "XY" + original
    typealias Step = (String, (Rig) -> Void)
    let scenarios: [[Step]] = [
        [],                                                  // the user's selection alone
        [("app sets selection only: 4..<6", { $0.setSel?(sel(original, 4, 6)) })],
        [("app sets text only: \"XY\" + old", { $0.setText?(inserted) })],
        [("app sets text \"XY\" + old AND selection 4..<9 (the old one, shifted)", { $0.setBoth?(inserted, sel(inserted, 4, 9)) })],
        [("app sets text only: old + \"XYZ\"", { $0.setText?(original + "XYZ") })],
        [("app sets text only: \"0123456789\"", { $0.setText?("0123456789") })],
        [("app sets text only: \"012\" (the selection now runs past the end)", { $0.setText?("012") })],
        [("app sets text \"012\" and selection nil", { $0.setBoth?("012", nil) })],
        [("app sets text \"XY\" + old, then (next turn) selection 4..<9", { $0.setText?(inserted) }),
         ("... then selection 4..<9", { $0.setSel?(sel(inserted, 4, 9)) })],
    ]
    // The past-the-end scenario TRAPS inside SwiftUI (see README), so it runs only on request:
    // PROBE_PAST_END=TextEditor or =TextField runs that one scenario for that view, and nothing else.
    let pastEnd = ProcessInfo.processInfo.environment["PROBE_PAST_END"]
    for field in [false, true] {
        let name = field ? "TextField" : "TextEditor"
        for (i, steps) in scenarios.enumerated() {
            let isPastEnd = steps.first?.0.contains("past the end") == true
            if let pastEnd { if !isPastEnd || pastEnd != name { continue } }
            else if isPastEnd { print("| \(name) | \(steps[0].0) | (skipped: traps; run with PROBE_PAST_END=\(name)) | | | |"); continue }
            _ = i
            let rig = Rig()
            let h: NSView = field ? NSHostingView(rootView: SelField(rig: rig)) : NSHostingView(rootView: SelEditor(rig: rig))
            _ = window(h)
            spin()
            guard let tv = focus(h, field: field) else { print("| \(name) | no text view found | | | | |"); continue }
            tv.setSelectedRange(startSel)
            spin(0.2)
            func row(_ label: String) {
                let now = current(h, field: field)
                let t = rig.getText?() ?? "-"
                print("| \(name) | \(label) | \(show(now?.string ?? "-")) | \(now.map { r($0.selectedRange()) } ?? "-") | \(show(t)) | \(describe(rig.getSel?() ?? nil, in: t)) |")
            }
            row("(after the user's selection {2,5})")
            for (label, act) in steps {
                act(rig)
                spin(0.3); h.layoutSubtreeIfNeeded(); spin(0.1)
                row(label)
            }
        }
    }
    print()
}

// MARK: - Part 5: macOS 26 API

@available(macOS 26, *)
struct AttrEditor: View {
    @State var text = AttributedString(original)
    @State var selection = AttributedTextSelection()
    var body: some View { TextEditor(text: $text, selection: $selection) }
}

@MainActor func part5() {
    print("## Part 5: macOS 26 API\n")
    if #available(macOS 26, *) {
        var text = AttributedString(original)
        let lo = text.index(text.startIndex, offsetByCharacters: 2), hi = text.index(text.startIndex, offsetByCharacters: 7)
        var selection = AttributedTextSelection(range: lo..<hi)
        text.transform(updating: &selection) { $0.insert(AttributedString("XY"), at: $0.startIndex) }
        print("- SwiftUI transform(updating: &AttributedTextSelection), insert \"XY\" at 0: \(String(text.characters)), selection \(selection.indices(in: text))")
        var t2 = AttributedString(original)
        var range = t2.index(t2.startIndex, offsetByCharacters: 2)..<t2.index(t2.startIndex, offsetByCharacters: 7)
        t2.transform(updating: &range) { $0.insert(AttributedString("XY"), at: $0.startIndex) }
        print("- Foundation transform(updating: &Range), insert \"XY\" at 0: \(String(t2.characters)), range \(t2.characters.distance(from: t2.startIndex, to: range.lowerBound))..<\(t2.characters.distance(from: t2.startIndex, to: range.upperBound))")
        _ = AttrEditor()
    } else {
        print("- compiled against the macOS \(sdk) SDK; NOT runnable here: the runtime is macOS \(ProcessInfo.processInfo.operatingSystemVersionString), and every one of these is `@available(macOS 26, *)`.")
    }
    print()
}
let sdk = "26.2"

@main struct Probe {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IONBF, 0)    // a trap mid-part still shows the rows before it
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            if ProcessInfo.processInfo.environment["PROBE_PAST_END"] != nil { part4(); return }
            if ProcessInfo.processInfo.environment["PROBE_EDGES"] != nil { part1b(); return }
            part1(); fflush(stdout)
            part2(); fflush(stdout)
            part3(); fflush(stdout)
            part4(); fflush(stdout)
            part5()
            print("== end")
        }
    }
}
