import SwiftUI
import AppKit

func all<T: NSView>(_ v: NSView, _ t: T.Type) -> [T] {
    var out: [T] = []
    if let x = v as? T { out.append(x) }
    for c in v.subviews { out += all(c, t) }
    return out
}

@MainActor func host<V: View>(_ view: V, size: NSSize = NSSize(width: 400, height: 300)) -> NSView {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    return host
}

func describe(_ a: NSAttributedString?) -> String {
    guard let a else { return "nil" }
    var parts: [String] = []
    a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { attrs, range, _ in
        let s = (a.string as NSString).substring(with: range)
        var tags: [String] = []
        if let f = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: f)
            if traits.contains(.boldFontMask) { tags.append("bold") }
            if traits.contains(.italicFontMask) { tags.append("italic") }
            tags.append(f.fontName)
        }
        if attrs[.strikethroughStyle] != nil { tags.append("strike") }
        parts.append("[\(s)|\(tags.joined(separator: ","))]")
    }
    return parts.joined()
}

struct Row: Identifiable { let id = 1; let name = "x" }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    // TextField title (placeholder)
    let tf = host(TextField("**Bold** and *it*", text: .constant("")))
    for f in all(tf, NSTextField.self) {
        print("TextField placeholderString:", f.placeholderString as Any)
        print("TextField placeholderAttributed:", describe(f.placeholderAttributedString))
        print("TextField stringValue:", f.stringValue)
    }
    // TextField with prompt Text
    let tf2 = host(TextField("Title", text: .constant(""), prompt: Text("**Bold** prompt")))
    for f in all(tf2, NSTextField.self) {
        print("TextField(prompt:) placeholderString:", f.placeholderString as Any)
        print("TextField(prompt:) placeholderAttributed:", describe(f.placeholderAttributedString))
    }
    // TableColumn header
    let table = host(Table([Row()]) { TableColumn("**Name** *x*", value: \.name) })
    for t in all(table, NSTableView.self) {
        for c in t.tableColumns {
            print("TableColumn header string:", c.headerCell.stringValue, "title:", c.title)
            print("TableColumn header attributed:", describe(c.headerCell.attributedStringValue))
        }
    }
    // Tab title
    let tabs = host(TabView { Tab("**Bold** tab", systemImage: "star") { Text("A") }; Tab("Plain", systemImage: "star") { Text("B") } })
    for tv in all(tabs, NSTabView.self) {
        for item in tv.tabViewItems { print("NSTabView item label:", item.label) }
    }
    for seg in all(tabs, NSSegmentedControl.self) {
        for i in 0..<seg.segmentCount { print("segment label:", seg.label(forSegment: i) as Any) }
    }
    for b in all(tabs, NSButton.self) { print("button title:", b.title, "attributed:", describe(b.attributedTitle)) }
    for f in all(tabs, NSTextField.self) { print("tabs textfield:", describe(f.attributedStringValue)) }
}
