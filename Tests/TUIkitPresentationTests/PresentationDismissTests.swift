//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationDismissTests.swift
//
//  `@Environment(\.dismiss)` inside a presentation used to QUIT THE APP.
//
//  `DismissAction`'s default action is `nil`, and calling a `nil` one exits the
//  run loop — correct at the top level, where dismissing a terminal app is
//  quitting it. But no presentation modifier replaced it, so the shape
//  SwiftUI's own documentation teaches —
//
//      .sheet(isPresented: $showing) {
//          Button("Done") { dismiss() }        // @Environment(\.dismiss)
//      }
//
//  — terminated the program instead of closing the sheet. Only
//  `NavigationStack` installed a real action, so only a pushed screen behaved.
//
//  These pin the fix at the seam that broke: whether the presented content's
//  environment carries an action at all. `requestExit()` is the failure mode,
//  so the test asserts the binding closes AND that nothing asked to exit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkitApp
@testable import TUIkitFoundation
import TUIkitPresentation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("dismiss() closes the presentation, not the app")
struct PresentationDismissTests {

    /// Captures whatever `\.dismiss` means where it is placed.
    private struct Capture: View {
        @Environment(\.dismiss) private var dismiss
        let sink: DismissSink

        var body: some View {
            sink.captured = dismiss
            return Text(verbatim: "presented")
        }
    }

    /// A box, because the capture happens during a render and is read after.
    private final class DismissSink: @unchecked Sendable {
        var captured: DismissAction?
    }

    private struct Presented: Hashable, Identifiable {
        let id = 1
    }

    /// Renders `view` one frame the way the run loop does, and returns the
    /// context it rendered in: its render state is what a top-level
    /// `dismiss()` asks to exit.
    @discardableResult
    private func frame(_ view: some View) -> TUIContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 60
        let context = RenderContext(
            availableWidth: 60, availableHeight: 20, environment: environment, tuiContext: tui)
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        environment.focusManager?.endRenderPass()
        return tui
    }

    /// Presents `content` through `present`, runs the `\.dismiss` it saw, and
    /// reports what that did.
    ///
    /// - Returns: Whether the presentation binding closed, and whether anything
    ///   asked the run loop to exit — the bug's signature.
    private func dismissFromInside(
        _ present: (Binding<Bool>, @escaping () -> AnyView) -> AnyView
    ) throws -> (closed: Bool, askedToExit: Bool) {
        let sink = DismissSink()
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })

        let tui = frame(present(binding, { AnyView(Capture(sink: sink)) }))

        let dismiss = try #require(sink.captured, "the presented content never rendered")
        dismiss()
        return (closed: !box.value, askedToExit: tui.appState.consumeShouldExit())
    }

    @Test("a sheet's own Done button closes the sheet")
    func sheet() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").sheet(isPresented: isPresented) { content() })
        }
        #expect(result.closed, "dismiss() should close the sheet")
        #expect(!result.askedToExit, "dismiss() must NOT quit the application")
    }

    @Test("a full-screen cover dismisses itself")
    func fullScreenCover() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(
                Text(verbatim: "page").fullScreenCover(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    @Test("a modal dismisses itself")
    func modal() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").modal(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    @Test("a popover dismisses itself")
    func popover() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").popover(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    /// The `item:` form funnels through the same modifier, but its binding is
    /// derived — worth pinning that clearing it is what dismissal does.
    @Test("a sheet presented by item clears the item")
    func sheetByItem() throws {
        let sink = DismissSink()
        let box = StateBox<Presented?>(Presented())
        let item = Binding(get: { box.value }, set: { box.value = $0 })

        let tui = frame(Text(verbatim: "page").sheet(item: item) { _ in Capture(sink: sink) })

        let dismiss = try #require(sink.captured)
        dismiss()
        #expect(box.value == nil, "dismiss() should clear the item binding")
        #expect(!tui.appState.consumeShouldExit(), "and must not quit the application")
    }

    /// `\.isPresented` is the read-only companion: the same presentations that
    /// publish a dismissal publish the flag, so a view can tell whether
    /// `dismiss()` will close something or quit.
    @Test("isPresented is true inside a presentation and false outside one")
    func isPresentedFlag() throws {
        let sink = FlagSink()
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })

        frame(Text(verbatim: "page").sheet(isPresented: binding) { FlagProbe(sink: sink) })
        #expect(sink.inside == true, "inside a sheet")

        frame(FlagProbe(sink: sink))
        #expect(sink.inside == false, "at the top level, nothing presented it")
    }

    private final class FlagSink: @unchecked Sendable {
        var inside: Bool?
    }

    private struct FlagProbe: View {
        @Environment(\.isPresented) private var isPresented
        let sink: FlagSink

        var body: some View {
            sink.inside = isPresented
            return Text(verbatim: "probe")
        }
    }

    /// The top-level meaning is unchanged: outside any presentation, dismissing
    /// a terminal app IS quitting it — the app the view is drawn in, and no
    /// other in the process, wherever the action is called from.
    @Test("outside a presentation, dismiss() still means quit, and quits its own app")
    func topLevelStillExits() throws {
        let sink = DismissSink()
        let tui = frame(Capture(sink: sink))
        let bystander = frame(Text(verbatim: "another app"))
        let dismiss = try #require(sink.captured, "the content never rendered")
        dismiss()
        #expect(tui.appState.consumeShouldExit(), "the top-level action must still exit")
        #expect(!bystander.appState.consumeShouldExit(), "another app was asked to exit")
    }

    /// `DismissAction()` names no app: it quits the one whose work calls it
    /// (`AmbientApp`) — an event handler's, a task's — and outside every app's
    /// work it does nothing.
    @Test("DismissAction() quits the app whose work calls it")
    func bareActionQuitsTheAmbientApp() {
        let app = AppState()
        AmbientApp.$renderState.withValue(app) { DismissAction()() }
        #expect(app.consumeShouldExit())
        DismissAction()()
        #expect(!app.consumeShouldExit(), "called on no app's task, it asked an app to exit")
    }
}
