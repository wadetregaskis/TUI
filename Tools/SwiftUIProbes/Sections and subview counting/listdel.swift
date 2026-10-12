import SwiftUI
import AppKit

@MainActor func findTables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for s in v.subviews { out += findTables(s) }
    return out
}

@MainActor final class Model: ObservableObject {
    @Published var items = ["a", "b", "c"]
    @Published var selection: Set<String> = []
    var log: [String] = []
}

struct Probe: View {
    @ObservedObject var model: Model
    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.items, id: \.self) { item in
                Text("\(item)1")
                Text("\(item)2")
            }
            .onDelete { offsets in
                model.log.append("delete \(Array(offsets))")
                model.items.remove(atOffsets: offsets)
            }
            .onMove { source, dest in
                model.log.append("move \(Array(source)) -> \(dest)")
            }
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let model = Model()
            NSApplication.shared.setActivationPolicy(.accessory)
            let h = NSHostingView(rootView: Probe(model: model))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
            let w = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = h
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            spin(0.5)
            guard let table = findTables(h).first else { print("no table"); return }
            print("rows:", table.numberOfRows)
            for r in 0..<table.numberOfRows {
                print(" row", r, String(describing: table.view(atColumn: 0, row: r, makeIfNecessary: true).map { type(of: $0) }))
            }
            // Select the SECOND row (element a's second view) and delete.
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            spin(0.3)
            print("selection:", model.selection)
            table.window?.makeFirstResponder(table)
            let handled = NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: table)
            spin(0.3)
            print("delete: handled \(handled) log \(model.log) items \(model.items) rows \(table.numberOfRows)")
            // Try the Delete key event too.
            table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
            spin(0.3)
            print("selection2:", model.selection)
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: table.window!.windowNumber, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51) {
                print("key window:", NSApp.keyWindow === table.window, "first responder:", String(describing: table.window?.firstResponder))
                NSApp.sendEvent(ev)
            }
            spin(0.3)
            print("after sendEvent: log \(model.log)")
            for sel in [#selector(NSText.delete(_:)), #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:))] {
                var r: NSResponder? = table
                while let cur = r {
                    if cur.responds(to: sel) { print("responds", sel, type(of: cur)); let ok = cur.tryToPerform(sel, with: nil); print(" performed", ok); break }
                    r = cur.nextResponder
                }
                spin(0.3)
                print(" log after \(sel): \(model.log) items \(model.items)")
            }
            // The responder chain's delete: as the Edit menu sends it.
            let target = NSApp.target(forAction: #selector(NSText.delete(_:)), to: nil, from: nil)
            print("delete target:", String(describing: target))
            spin(0.3)
            print("deleteKey: log \(model.log) items \(model.items) rows \(table.numberOfRows)")
        }
    }
}
