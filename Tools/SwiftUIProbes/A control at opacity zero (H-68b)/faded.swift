import AppKit
import SwiftUI

// Whether a control drawn at opacity zero takes a click, and whether Tab stops
// on it (bug hunt H-68b, after `Layers over a control (H-68)`, whose last case
// found a button at `.opacity(0)` takes no click).
//
//   click  a press and a release at the centre of a 200 × 200 window holding a
//          button, bordered (AppKit's control under SwiftUI) and plain (SwiftUI's
//          own hit testing, its label a 120 × 40 grey field), faded out in each
//          of the ways below; prints whether its action ran.
//   tab    `VStack { TextField("first"); <middle>; TextField("last") }` with the
//          focus on "first", then one Tab: prints the field `@FocusState` names.
//          The middle is a text field, a `.focusable()` view and a bordered button,
//          each at opacity 1 (the control) and 0. A button is a Tab stop on macOS
//          only under Full Keyboard Access, so the line prints that setting.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 faded.swift -o "$TMPDIR/faded"
//   "$TMPDIR/faded"

@MainActor var clicks = 0
@MainActor var keep: [NSWindow] = []

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor func window<V: View>(_ view: V) -> (NSWindow, NSView) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
    let window = KeyableWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: host.frame.size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    keep.append(window)
    return (window, host)
}

enum Style: String, CaseIterable { case bordered, plain }

enum Fade: String, CaseIterable {
    case none = "opacity 1 (control)"
    case zero = ".opacity(0)"
    case faint = ".opacity(0.01)"
    case faint2 = ".opacity(0.02)"
    case faint22 = ".opacity(0.022)"
    case faint201 = ".opacity(0.0201)"
    case faint205 = ".opacity(0.0205)"
    case faint208 = ".opacity(0.0208)"
    case faint209 = ".opacity(0.0209)"
    case faint21 = ".opacity(0.021)"
    case faint3 = ".opacity(0.03)"
    case faint4 = ".opacity(0.04)"
    case faint5 = ".opacity(0.05)"
    case tenth = ".opacity(0.1)"
    case half = ".opacity(0.5)"
    case ancestor = "VStack { button }.opacity(0)"
    case restored = ".opacity(0).opacity(1)"
    case nested = ".opacity(0.1).opacity(0.1)"
    case nestedHalf = ".opacity(0.1).opacity(0.5)"
    case animated = ".opacity(0) set by an animation"
}

struct Clickable: View {
    let style: Style
    let fade: Fade
    @State var faded = false
    var body: some View {
        let button = Group {
            switch style {
            case .bordered: Button("Save") { clicks += 1 }
            case .plain:
                Button { clicks += 1 } label: { Color.gray.frame(width: 120, height: 40) }
                    .buttonStyle(.plain)
            }
        }
        Group {
            switch fade {
            case .none: button
            case .zero: button.opacity(0)
            case .faint: button.opacity(0.01)
            case .faint2: button.opacity(0.02)
            case .faint22: button.opacity(0.022)
            case .faint201: button.opacity(0.0201)
            case .faint205: button.opacity(0.0205)
            case .faint208: button.opacity(0.0208)
            case .faint209: button.opacity(0.0209)
            case .faint21: button.opacity(0.021)
            case .faint3: button.opacity(0.03)
            case .faint4: button.opacity(0.04)
            case .faint5: button.opacity(0.05)
            case .tenth: button.opacity(0.1)
            case .half: button.opacity(0.5)
            case .ancestor: VStack { button }.opacity(0)
            case .restored: button.opacity(0).opacity(1)
            case .nested: button.opacity(0.1).opacity(0.1)
            case .nestedHalf: button.opacity(0.1).opacity(0.5)
            case .animated:
                button.opacity(faded ? 0 : 1)
                    .onAppear { withAnimation(.linear(duration: 0.1)) { faded = true } }
            }
        }
        .frame(width: 200, height: 200)
    }
}

@MainActor func mouse(_ window: NSWindow, _ type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
}

@MainActor func click(_ fade: Fade) async {
    for style in Style.allCases {
        clicks = 0
        let (w, _) = window(Clickable(style: style, fade: fade))
        try? await Task.sleep(for: .milliseconds(450))
        NSApp.postEvent(mouse(w, .leftMouseDown), atStart: false)
        NSApp.postEvent(mouse(w, .leftMouseUp), atStart: false)
        try? await Task.sleep(for: .milliseconds(450))
        let name = "\(fade.rawValue), \(style.rawValue)".padding(toLength: 44, withPad: " ", startingAt: 0)
        print("click \(name) \(clicks > 0 ? "TAKEN" : "not taken") (actions \(clicks))")
        w.orderOut(nil)
    }
}

enum Field: Hashable { case first, middle, last }
enum Middle: String, CaseIterable { case textField = "TextField", focusable = ".focusable() view", button = "bordered Button" }

@MainActor var focusedField: Field?

struct Tabbing: View {
    let middle: Middle
    let opacity: Double
    @FocusState var focus: Field?
    var body: some View {
        VStack {
            TextField("first", text: .constant("")).focused($focus, equals: .first)
            Group {
                switch middle {
                case .textField: TextField("middle", text: .constant(""))
                case .focusable: Color.gray.frame(width: 60, height: 20).focusable()
                case .button: Button("Middle") {}
                }
            }
            .focused($focus, equals: .middle)
            .opacity(opacity)
            TextField("last", text: .constant("")).focused($focus, equals: .last)
        }
        .padding()
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            focus = .first
        }
        .onChange(of: focus) { _, new in focusedField = new }
    }
}

@MainActor func tab(_ middle: Middle, opacity: Double) async {
    focusedField = nil
    let (w, _) = window(Tabbing(middle: middle, opacity: opacity))
    try? await Task.sleep(for: .milliseconds(450))
    // The field editor's text field, if a text field holds the focus.
    let editor = (w.firstResponder as? NSTextView)?.delegate as? NSTextField
    let before = editor?.placeholderString ?? String(describing: w.firstResponder.map { type(of: $0) })
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: w.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48)!
        w.sendEvent(event)
    }
    try? await Task.sleep(for: .milliseconds(450))
    let after = focusedField.map { "\($0)" } ?? "nil"
    let name = "\(middle.rawValue) at opacity \(opacity == 0 ? "0" : "1")".padding(toLength: 40, withPad: " ", startingAt: 0)
    print("tab   \(name) first responder '\(before)' -> Tab -> @FocusState \(after)")
    w.orderOut(nil)
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.finishLaunching()
            print("macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Full Keyboard Access (NSApp.isFullKeyboardAccessEnabled): \(NSApp.isFullKeyboardAccessEnabled)")
            Task { @MainActor in
                for fade in Fade.allCases { await click(fade) }
                for middle in Middle.allCases {
                    await tab(middle, opacity: 1)
                    await tab(middle, opacity: 0)
                }
                exit(0)
            }
            NSApp.run()
        }
    }
}
