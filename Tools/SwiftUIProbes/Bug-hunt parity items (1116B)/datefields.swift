import AppKit
import SwiftUI

// Whether a `DatePicker` keeps the components it does not show when the user
// edits one it does (bug hunt 1116B, 2026-11-16). The bound date starts at
// 2026-03-14 09:26:37.250 (UTC, with a quarter second); the picker shows
// `.hourAndMinute`, `.date`, or both, in the default (stepper field) style.
// Its NSDatePicker is the first responder; a key goes to it as AppKit
// delivers one (`NSWindow.sendEvent`). Up steps the field that has the
// keyboard (the first one at the start), Tab moves to the next field. After
// each step the bound date is printed in full (to the millisecond, UTC), and
// what the NSDatePicker itself holds.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 datefields.swift -o "$TMPDIR/datefields"
//   "$TMPDIR/datefields"

@MainActor final class Model: ObservableObject {
    @Published var date: Date
    init(_ date: Date) { self.date = date }
}

enum Shown: String, CaseIterable { case hourAndMinute, date, both }

struct Probe: View {
    let shown: Shown
    @ObservedObject var m: Model
    var body: some View {
        switch shown {
        case .hourAndMinute: DatePicker("When", selection: $m.date, displayedComponents: .hourAndMinute)
        case .date: DatePicker("When", selection: $m.date, displayedComponents: .date)
        case .both: DatePicker("When", selection: $m.date, displayedComponents: [.date, .hourAndMinute])
        }
    }
}

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews { if let match = find(type, in: sub) { return match } }
    return nil
}

let utc = TimeZone(identifier: "UTC")!
let format: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = utc
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

@MainActor func send(_ characters: String, keyCode: UInt16, window: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
        window.sendEvent(event)
    }
    spin()
}

let up = (String(UnicodeScalar(NSUpArrowFunctionKey)!), UInt16(126))
let tab = ("\t", UInt16(48))

@MainActor func run(_ shown: Shown) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let start = calendar.date(from: DateComponents(
        year: 2026, month: 3, day: 14, hour: 9, minute: 26, second: 37, nanosecond: 250_000_000))!
    let m = Model(start)
    let window = KeyWindow(
        contentRect: NSRect(x: 200, y: 300, width: 360, height: 120), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: Probe(shown: shown, m: m).environment(\.timeZone, utc))
    window.makeKeyAndOrderFront(nil)
    spin(0.6)
    guard let picker = find(NSDatePicker.self, in: window.contentView!) else { print(shown, "no picker"); return }
    window.makeFirstResponder(picker)
    spin()
    func state(_ step: String) {
        print("  \(step): bound \(format.string(from: m.date)), picker \(format.string(from: picker.dateValue))")
    }
    print("\(shown.rawValue): picker elements \(picker.datePickerElements.rawValue), style \(picker.datePickerStyle.rawValue), "
        + "time zone \(picker.timeZone?.identifier ?? "nil"), first responder \(type(of: window.firstResponder!))")
    state("start")
    send(up.0, keyCode: up.1, window: window); state("Up in the first field")
    send(tab.0, keyCode: tab.1, window: window)
    send(up.0, keyCode: up.1, window: window); state("Tab, Up in the second field")
    window.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString, "locale", Locale.current.identifier)
            for shown in Shown.allCases { run(shown) }
        }
    }
}
