import AppKit

// MENUBAR-KEYS (owner, 2026-11-10 evening): how does an AppKit menu answer the
// arrows? A pop-up NSMenu is opened (nothing highlighted, as the pointer opens
// one), and a timer inside its tracking loop posts one key at a time to the
// app's own queue (`NSApp.postEvent`, no Accessibility grant needed) and reads
// the highlighted item after each. Questions: which row does the first Down
// take with a disabled first item; does Up from the first item wrap to the
// last; does Down from the last wrap; what does Up take from nothing; does
// Right on a submenu's row open it and highlight its first row; does Left in
// the submenu come back to the row.
//
//   swiftc -parse-as-library walk.swift -o /tmp/walk && /tmp/walk

final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

enum Arrow: String {
    case up, down, left, right, escape
    var character: String {
        switch self {
        case .up: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case .down: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .left: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case .right: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case .escape: "\u{1B}"
        }
    }
    var keyCode: UInt16 {
        switch self {
        case .up: 126
        case .down: 125
        case .left: 123
        case .right: 124
        case .escape: 53
        }
    }
}

@MainActor func post(_ arrow: Arrow, window: NSWindow) {
    let flags: NSEvent.ModifierFlags = arrow == .escape ? [] : [.numericPad, .function]
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: arrow.character,
            charactersIgnoringModifiers: arrow.character, isARepeat: false, keyCode: arrow.keyCode)!
        NSApp.postEvent(event, atStart: false)
    }
}

/// The menu's and every open submenu's highlighted item, outermost first.
@MainActor func highlights(_ menu: NSMenu) -> String {
    var parts: [String] = []
    var current: NSMenu? = menu
    while let level = current {
        let item = level.highlightedItem
        parts.append(item?.title ?? "none")
        current = item?.submenu
    }
    return parts.joined(separator: " > ")
}

@MainActor func run(_ name: String, keys: [Arrow], menu: NSMenu, window: NSWindow) {
    var log: [String] = ["open: \(highlights(menu))"]
    var step = 0
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
        MainActor.assumeIsolated {
            if step > 0 { log.append("\(keys[step - 1].rawValue): \(highlights(menu))") }
            if step == keys.count {
                menu.cancelTracking()
                return
            }
            post(keys[step], window: window)
            step += 1
        }
    }
    RunLoop.main.add(timer, forMode: .eventTracking)
    menu.popUp(positioning: nil, at: NSPoint(x: 20, y: 80), in: window.contentView)
    timer.invalidate()
    print("\(name): " + log.joined(separator: " | "))
}

@MainActor func makeMenu(disabledFirst: Bool = true) -> NSMenu {
    let menu = NSMenu(title: "Probe")
    menu.autoenablesItems = false
    if disabledFirst {
        let zero = NSMenuItem(title: "Zero (disabled)", action: nil, keyEquivalent: "")
        zero.isEnabled = false
        menu.addItem(zero)
        menu.addItem(.separator())
    }
    for title in ["One", "Two", "Three"] {
        let item = NSMenuItem(title: title, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        item.isEnabled = true
        menu.addItem(item)
    }
    let sub = NSMenu(title: "Sub")
    sub.autoenablesItems = false
    for title in ["S1", "S2"] {
        let item = NSMenuItem(title: title, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        sub.addItem(item)
    }
    let more = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
    more.submenu = sub
    menu.addItem(more)
    return menu
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setbuf(stdout, nil)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let window = KeyWindow(
                contentRect: NSRect(x: 200, y: 300, width: 300, height: 200), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.makeKeyAndOrderFront(nil)
            spin(0.5)
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            run("down-from-nothing", keys: [.down, .up, .up], menu: makeMenu(), window: window)
            run("up-from-nothing", keys: [.up, .down, .down], menu: makeMenu(), window: window)
            run("down-to-the-end", keys: [.down, .down, .down, .down, .down], menu: makeMenu(), window: window)
            run("submenu", keys: [.up, .right, .down, .left, .left, .right, .right], menu: makeMenu(), window: window)
            run("up-from-first, no disabled row", keys: [.down, .up, .up], menu: makeMenu(disabledFirst: false), window: window)
            run("across-from-nothing", keys: [.left, .right], menu: makeMenu(), window: window)
            exit(0)
        }
    }
}
