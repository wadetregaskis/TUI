import AppKit
import SwiftUI

// What `.sheet(item:onDismiss:)` does when the app replaces the item while
// the sheet is up (bug hunt 1116B, 2026-11-16): is it dismissed (onDismiss
// runs) and presented again for the new item, or does the sheet stay and show
// the new item? Logs onDismiss, the sheet content's onAppear/onDisappear (with
// the item it was made for), the item changes it sees and the sheet's
// `@State` serial, and whether the window's attached sheet is the same one.
// Steps: item A; A replaced by B; B replaced by an equal-id item with other
// contents (B'); then nil.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 sheetitem.swift -o "$TMPDIR/sheetitem"
//   "$TMPDIR/sheetitem"

struct Item: Identifiable {
    let id: String
    var note: String
}

@MainActor enum Log {
    static var lines: [String] = []
    static var serial = 0
    static func add(_ line: String) { lines.append(line) }
}

@MainActor final class Model: ObservableObject {
    @Published var item: Item?
}

struct SheetContent: View {
    let item: Item
    @State private var serial: Int = {
        MainActor.assumeIsolated {
            Log.serial += 1
            return Log.serial
        }
    }()
    var body: some View {
        Text("\(item.id) \(item.note) state#\(serial)")
            .frame(width: 200, height: 80)
            .onAppear { Log.add("content appear \(item.id) state#\(serial)") }
            .onDisappear { Log.add("content disappear \(item.id) state#\(serial)") }
            .onChange(of: item.id) { _, now in Log.add("content sees id \(now) state#\(serial)") }
            .onChange(of: item.note) { _, now in Log.add("content sees note \(now) state#\(serial)") }
    }
}

struct Probe: View {
    @ObservedObject var m: Model
    var body: some View {
        Color.clear
            .frame(width: 400, height: 300)
            .sheet(item: $m.item, onDismiss: { Log.add("onDismiss") }) { item in
                SheetContent(item: item)
            }
    }
}

@MainActor func spin(_ s: Double = 1.0) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            let m = Model()
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 300, width: 400, height: 300), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: Probe(m: m))
            window.makeKeyAndOrderFront(nil)
            spin()
            var lastSheet: NSWindow?
            @MainActor func step(_ label: String, _ change: () -> Void) {
                Log.lines = []
                change()
                spin(1.5)
                let sheet = window.attachedSheet
                let same = sheet.map { $0 === lastSheet } ?? false
                print("\(label): \(Log.lines); item \(m.item.map { "\($0.id) \($0.note)" } ?? "nil"); "
                    + "sheet \(sheet == nil ? "none" : (same ? "up, the same window" : "up, a new window"))")
                lastSheet = sheet
            }
            step("present A") { m.item = Item(id: "A", note: "one") }
            step("replace A with B") { m.item = Item(id: "B", note: "one") }
            step("replace B with B' (same id, new note)") { m.item = Item(id: "B", note: "two") }
            step("set nil") { m.item = nil }
        }
    }
}
