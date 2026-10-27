// A-MODALS-1 probe: what still works behind a window-modal sheet and an
// app-modal alert on macOS? Three kinds of command:
//   ⌘K  an APP command (main menu item whose target is the app delegate)
//   ⌘J  a WINDOW command (main menu item, nil target: the responder chain of
//       the key window, implemented by the document window's view)
//   ⌘B  a BUTTON's key equivalent inside the document window
// Each invocation is logged to modalkeys.out beside the binary, with what was
// modal at the time. Menu validation is logged as well, so the log says
// whether a menu item was enabled when the menu was opened.
//
//   swiftc -O modalkeys.swift -o modalkeys && ./modalkeys
import AppKit

let logURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("modalkeys.out")
try? Data().write(to: logURL)

func log(_ line: String) {
    let stamp = String(format: "%.2f", ProcessInfo.processInfo.systemUptime)
    let text = "\(stamp) \(line)\n"
    print(text, terminator: "")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    }
}

var modalState: String {
    var parts: [String] = []
    if let sheet = docWindow.attachedSheet { parts.append("sheet '\(sheet.title)' up") }
    if NSApp.modalWindow != nil { parts.append("app-modal up") }
    return parts.isEmpty ? "nothing modal" : parts.joined(separator: ", ")
}

final class DocView: NSView, NSMenuItemValidation {
    @objc func windowCommand(_ sender: Any?) { log("⌘J window command RAN (\(modalState))") }
    @objc func buttonPressed(_ sender: Any?) { log("⌘B button RAN (\(modalState))") }
    override var acceptsFirstResponder: Bool { true }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        log("validate '\(item.title)' -> enabled (\(modalState))")
        return true
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    @objc func appCommand(_ sender: Any?) { log("⌘K app command RAN (\(modalState))") }

    @objc func showSheet(_ sender: Any?) {
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Sheet"
        let close = NSButton(title: "Close sheet", target: self, action: #selector(closeSheet(_:)))
        close.frame = NSRect(x: 90, y: 40, width: 120, height: 32)
        close.keyEquivalent = "\u{1b}"
        sheet.contentView?.addSubview(close)
        log("sheet shown")
        docWindow.beginSheet(sheet)
    }

    @objc func closeSheet(_ sender: Any?) {
        if let sheet = docWindow.attachedSheet { docWindow.endSheet(sheet) }
        log("sheet closed")
    }

    @objc func showAlert(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "App-modal alert"
        alert.informativeText = "Press ⌘K, ⌘J, ⌘B, then OK."
        log("app-modal alert shown")
        alert.runModal()
        log("app-modal alert closed")
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        log("validate '\(item.title)' -> enabled (\(modalState))")
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate

let mainMenu = NSMenu()
let appItem = NSMenuItem(); mainMenu.addItem(appItem)
let appMenu = NSMenu(); appItem.submenu = appMenu
appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let testItem = NSMenuItem(); mainMenu.addItem(testItem)
let testMenu = NSMenu(title: "Test"); testItem.submenu = testMenu
let k = testMenu.addItem(withTitle: "App command", action: #selector(Delegate.appCommand(_:)), keyEquivalent: "k")
k.target = delegate
testMenu.addItem(withTitle: "Window command", action: #selector(DocView.windowCommand(_:)), keyEquivalent: "j")
app.mainMenu = mainMenu

let docWindow = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 420, height: 220),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
docWindow.title = "Modal keys probe"
let view = DocView(frame: docWindow.contentRect(forFrameRect: docWindow.frame))
docWindow.contentView = view
let button = NSButton(title: "Button (⌘B)", target: view, action: #selector(DocView.buttonPressed(_:)))
button.frame = NSRect(x: 20, y: 150, width: 160, height: 32)
button.keyEquivalent = "b"; button.keyEquivalentModifierMask = .command
view.addSubview(button)
let sheetButton = NSButton(title: "Show sheet", target: delegate, action: #selector(Delegate.showSheet(_:)))
sheetButton.frame = NSRect(x: 20, y: 100, width: 160, height: 32)
view.addSubview(sheetButton)
let alertButton = NSButton(title: "Show app-modal alert", target: delegate, action: #selector(Delegate.showAlert(_:)))
alertButton.frame = NSRect(x: 20, y: 50, width: 200, height: 32)
view.addSubview(alertButton)
docWindow.makeKeyAndOrderFront(nil)
docWindow.makeFirstResponder(view)
app.activate(ignoringOtherApps: true)
log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
app.run()
