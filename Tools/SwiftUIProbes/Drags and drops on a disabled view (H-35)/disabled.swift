import AppKit
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

// Whether SwiftUI takes a drop on, or starts a drag from, a view that
// `.disabled(true)` covers (bug hunt H-35, DND-5, 2026-11-23), for each of
// `dropDestination(for:)`, `onDrop(of:)`, `draggable(_:)` and `onDrag(_:)`,
// with the modifier inside the disabled scope (`.dropDestination(…)
// .disabled(true)`) and outside it (`.disabled(true).dropDestination(…)`).
//
// Drop: a string is offered to the view under the zone's centre that
// registers for strings, through an NSDraggingInfo of the probe's own (copy,
// generic and move offered, as an unmodified drag from another app does), as
// `Pasted line breaks and drops (1117)` does. The probe prints the operation
// draggingEntered and draggingUpdated chose, whether performDragOperation
// took it, and whether the action ran.
//
// Drag: a press, three drags and a release are posted to the window as
// synthetic events (the way `Gestures (lane 17g)` drives gestures), and
// `-[NSView beginDraggingSession(with:event:source:)]` is replaced by one
// that records the call and starts nothing, so the probe hears whether
// SwiftUI would have started a drag without AppKit's drag loop, which needs a
// real mouse, running at all.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 disabled.swift -o "$TMPDIR/disabled"
//   "$TMPDIR/disabled"

@MainActor var dropped: [String] = []
@MainActor var dragsBegun: [String] = []

enum Scope: String, CaseIterable { case enabled, inside = "disabled inside", outside = "disabled outside" }

enum Destination: String, CaseIterable { case dropDestination, onDrop }
enum Source: String, CaseIterable { case draggable, onDrag }

extension View {
    @ViewBuilder func scoped<Modified: View>(_ scope: Scope, _ modifier: (AnyView) -> Modified) -> some View {
        switch scope {
        case .enabled: modifier(AnyView(self))
        case .inside: modifier(AnyView(self)).disabled(true)
        case .outside: modifier(AnyView(self.disabled(true)))
        }
    }
}

func zone() -> some View { Color.blue.frame(width: 120, height: 60) }

@MainActor func destination(_ kind: Destination, _ scope: Scope) -> some View {
    zone().scoped(scope) { view -> AnyView in
        switch kind {
        case .dropDestination:
            AnyView(view.dropDestination(for: String.self) { items, _ in
                dropped.append("dropDestination \(items)")
                return true
            })
        case .onDrop:
            AnyView(view.onDrop(of: [.plainText], isTargeted: nil) { providers in
                dropped.append("onDrop \(providers.count)")
                return true
            })
        }
    }
}

@MainActor func source(_ kind: Source, _ scope: Scope) -> some View {
    zone().scoped(scope) { view -> AnyView in
        switch kind {
        case .draggable: AnyView(view.draggable("apple"))
        case .onDrag: AnyView(view.onDrag { NSItemProvider(object: "apple" as NSString) })
        }
    }
}

final class Drag: NSObject, NSDraggingInfo {
    let window: NSWindow
    let location: NSPoint
    let pasteboard: NSPasteboard
    init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard) {
        self.window = window
        self.location = location
        self.pasteboard = pasteboard
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic, .move] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
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

@MainActor func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if let event = NSApp.nextEvent(
            matching: .any, until: min(end, Date().addingTimeInterval(0.01)), inMode: .default, dequeue: true)
        {
            NSApp.sendEvent(event)
        }
    }
}

@MainActor func host(_ view: some View) -> (NSWindow, NSHostingView<AnyView>) {
    let size = CGSize(width: 200, height: 120)
    let hosting = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    pump(0.3)
    return (window, hosting)
}

@MainActor func drop(_ kind: Destination, _ scope: Scope) {
    dropped = []
    let (window, hosting) = host(destination(kind, scope))
    let centre = NSPoint(x: hosting.bounds.midX, y: hosting.bounds.midY)
    // SwiftUI's destination is a `_PlatformDraggingDestinationView` that
    // hit-testing never returns (it registers `public.data` and `public.item`
    // on macOS 15.8), so it is found by walking down: the innermost view under
    // the centre that registers any type.
    func registered(in view: NSView) -> NSView? {
        for child in view.subviews.reversed() {
            let local = child.convert(centre, from: hosting)
            guard child.bounds.contains(local) else { continue }
            if let found = registered(in: child) { return found }
        }
        return view.registeredDraggedTypes.isEmpty ? nil : view
    }
    let target = registered(in: hosting)
    let label = "drop on \(kind.rawValue), \(scope.rawValue)"
    guard let view = target else {
        func walk(_ view: NSView, _ depth: Int) {
            print(String(repeating: "  ", count: depth + 1)
                + "\(type(of: view)) \(view.frame) registers \(view.registeredDraggedTypes.map(\.rawValue))")
            for child in view.subviews { walk(child, depth + 1) }
        }
        print("\(label): no view under the zone registers for strings; hit \(hosting.hitTest(centre).map { "\(type(of: $0))" } ?? "nothing")")
        walk(hosting, 0)
        window.orderOut(nil)
        return
    }
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("DROP", forType: .string)
    let info = Drag(window: window, location: hosting.convert(centre, to: nil), pasteboard: pasteboard)
    let entered = view.draggingEntered(info)
    pump(0.1)
    let updated = view.draggingUpdated(info)
    var performed = false
    if !updated.isEmpty || !entered.isEmpty {
        let prepared = view.prepareForDragOperation(info)
        performed = prepared && view.performDragOperation(info)
        view.concludeDragOperation(info)
    } else {
        view.draggingExited(info)
    }
    pump(0.4)
    print("\(label), on \(type(of: view)): entered \(entered.rawValue), updated \(updated.rawValue), "
        + "performed \(performed), action ran \(dropped)")
    pasteboard.releaseGlobally()
    window.orderOut(nil)
}

@MainActor func drag(_ kind: Source, _ scope: Scope) {
    dragsBegun = []
    let (window, hosting) = host(source(kind, scope))
    let height = hosting.bounds.height
    func post(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) {
        let event = NSEvent.mouseEvent(
            with: type, location: NSPoint(x: x, y: height - y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        NSApp.postEvent(event, atStart: false)
        pump(0.08)
    }
    post(.leftMouseDown, 100, 60)
    post(.leftMouseDragged, 104, 62)
    post(.leftMouseDragged, 112, 66)
    post(.leftMouseDragged, 130, 80)
    post(.leftMouseUp, 130, 80)
    pump(0.3)
    print("drag from \(kind.rawValue), \(scope.rawValue): drag sessions begun \(dragsBegun)")
    window.orderOut(nil)
}

/// Replaces `-[NSView beginDraggingSession(with:event:source:)]` with one that
/// records the call and its items' types, and begins no session (an
/// NSDraggingSession has no public initialiser, so an unretained placeholder
/// object stands in for the return value; nothing the probe drives reads it).
@MainActor func recordDragSessions() {
    let selector = #selector(NSView.beginDraggingSession(with:event:source:))
    let method = class_getInstanceMethod(NSView.self, selector)!
    let block: @convention(block) (NSView, NSArray, NSEvent, AnyObject) -> AnyObject = { view, items, _, _ in
        let types = (items as? [NSDraggingItem] ?? []).flatMap { item -> [String] in
            guard let writer = item.item as? NSPasteboardWriting else { return ["?"] }
            return writer.writableTypes(for: NSPasteboard.general).map(\.rawValue)
        }
        MainActor.assumeIsolated { dragsBegun.append("\(type(of: view)) \(items.count) item(s) \(types.prefix(3))") }
        return NSObject()
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.finishLaunching()
            print("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            for kind in Destination.allCases { for scope in Scope.allCases { drop(kind, scope) } }
            recordDragSessions()
            for kind in Source.allCases { for scope in Scope.allCases { drag(kind, scope) } }
        }
    }
}
