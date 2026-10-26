//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogImplicitButtonTests.swift
//
//  A dialog draws the button SwiftUI adds when the app gave none (deviations
//  sweep, likely bug 15; semantic audit 39). An alert: "If no actions are
//  present, the system includes a standard "OK" action." A confirmation
//  dialog: "Dialogs include a standard dismiss action by default. If you
//  provide a button with a role of cancel, that button takes the place of the
//  default dismiss action."
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A dialog adds SwiftUI's implicit OK or Cancel")
struct DialogImplicitButtonTests {
    private func render(_ view: some View) -> String {
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
            .lines.joined(separator: "\n").stripped
    }

    @Test("An alert with no actions has an OK; one with actions has only its own")
    func alertOK() {
        let bare = render(
            Text("base").alert("Saved", isPresented: .constant(true)) {} message: { Text("All done.") })
        #expect(bare.contains("OK"), "\(bare)")
        let withActions = render(
            Text("base").alert("Saved", isPresented: .constant(true)) { Button("Thanks") {} })
        #expect(withActions.contains("Thanks") && !withActions.contains("OK"), "\(withActions)")
    }

    @Test("A confirmation dialog with no Cancel has one; one with its own cancel button has only that")
    func dialogCancel() {
        let bare = render(
            Text("base").confirmationDialog("Erase?", isPresented: .constant(true)) {
                Button("Empty Trash", role: .destructive) {}
            })
        #expect(bare.contains("Empty Trash") && bare.contains("Cancel"), "\(bare)")
        let own = render(
            Text("base").confirmationDialog("Erase?", isPresented: .constant(true)) {
                Button("Empty Trash", role: .destructive) {}
                Button("Keep", role: .cancel) {}
            })
        #expect(own.contains("Keep") && !own.contains("Cancel"), "\(own)")
    }

    // MARK: - Choosing the implicit button

    private final class Flag: @unchecked Sendable {
        var value = true
    }

    private struct Page: App {
        let flag: Flag
        init() { self.init(flag: Flag()) }
        init(flag: Flag) { self.flag = flag }
        var body: some Scene {
            WindowGroup {
                Text("base").alert(
                    "Saved", isPresented: Binding(get: { flag.value }, set: { flag.value = $0 })
                ) {} message: {
                    Text("All done.")
                }
            }
        }
    }

    @Test("Return on the implicit OK closes the alert")
    func okCloses() {
        let flag = Flag()
        let app = HeadlessApp(Page(flag: flag), width: 60, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        #expect(app.screen.contains { $0.stripped.contains("OK") }, "\(app.screen.map(\.stripped))")
        _ = app.send(KeyEvent(key: .enter))
        frame()
        frame()
        #expect(flag.value == false, "Return did not close the alert through its OK")
    }
}
