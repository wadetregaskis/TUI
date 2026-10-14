//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationCompactAdaptationTests.swift
//
//  A popover in a compact size class is a sheet, or what its content's
//  `presentationCompactAdaptation` asks for (decisions A21, B3). macOS is never
//  compact, so SwiftUI's side is iOS's documented behaviour: "a popover
//  presentation … in a horizontally compact size class … adapts to a sheet".
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitPresentation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Which size classes a page is drawn in.
@Observable
private final class SizeClasses: @unchecked Sendable {
    var horizontal: UserInterfaceSizeClass = .regular
    var vertical: UserInterfaceSizeClass = .regular
    var appearances = 0
}

@MainActor
@Suite("A popover adapts to a compact size class")
struct PresentationCompactAdaptationTests {
    private enum Form: Equatable {
        case popover, sheet, cover, none
    }

    private func context(width: Int = 40, height: Int = 20) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, _ in
            environment.mouseEventDispatcher = MouseEventDispatcher()
            environment.terminalWidth = width
            environment.overlayContentHeight = height
        }
    }

    /// The form a presented popover took, told by its overlay as
    /// PresentationVariantsTests tells them apart.
    private func form<V: View>(_ view: V, horizontal: UserInterfaceSizeClass, vertical: UserInterfaceSizeClass = .regular)
        -> Form
    {
        let buffer = renderToBuffer(
            view.environment(\.horizontalSizeClass, horizontal).environment(\.verticalSizeClass, vertical),
            context: context())
        guard buffer.overlays.count == 1 else { return .none }
        let overlay = buffer.overlays[0]
        if overlay.level == .popover { return .popover }
        if overlay.dimsBackground, overlay.centered { return .sheet }
        if !overlay.dimsBackground, overlay.offsetX == 0, overlay.offsetY == 0 { return .cover }
        return .none
    }

    @Test("In a regular size class a popover is a popover")
    func regularKeepsThePopover() {
        let view = Text("anchor").popover(isPresented: .constant(true)) { Text("detail") }
        #expect(form(view, horizontal: .regular) == .popover)
    }

    @Test("In a compact size class a popover is a sheet, either class")
    func compactMakesASheet() {
        let view = Text("anchor").popover(isPresented: .constant(true)) { Text("detail") }
        #expect(form(view, horizontal: .compact) == .sheet)
        #expect(form(view, horizontal: .regular, vertical: .compact) == .sheet)
    }

    @Test("The content's adaptation decides: none and popover keep it, fullScreenCover covers")
    func statedAdaptation() {
        func view(_ adaptation: PresentationAdaptation) -> some View {
            Text("anchor").popover(isPresented: .constant(true)) {
                Text("detail").presentationCompactAdaptation(adaptation)
            }
        }
        #expect(form(view(.none), horizontal: .compact) == .popover)
        #expect(form(view(.popover), horizontal: .compact) == .popover)
        #expect(form(view(.sheet), horizontal: .compact) == .sheet)
        #expect(form(view(.automatic), horizontal: .compact) == .sheet)
        #expect(form(view(.fullScreenCover), horizontal: .compact) == .cover)
        // Under another trait, as `interactiveDismissDisabled`'s is found.
        let beneath = Text("anchor").popover(isPresented: .constant(true)) {
            Text("detail").presentationCompactAdaptation(.none).interactiveDismissDisabled()
        }
        #expect(form(beneath, horizontal: .compact) == .popover)
    }

    @Test("Each class takes its own adaptation, and where both are compact the vertical one wins")
    func perClass() {
        let view = Text("anchor").popover(isPresented: .constant(true)) {
            Text("detail").presentationCompactAdaptation(horizontal: .none, vertical: .fullScreenCover)
        }
        #expect(form(view, horizontal: .compact) == .popover)
        #expect(form(view, horizontal: .regular, vertical: .compact) == .cover)
        #expect(form(view, horizontal: .compact, vertical: .compact) == .cover)
    }

    private struct Row: Identifiable {
        let id: Int
    }

    @Test("A popover for an item adapts too")
    func itemForm() {
        let view = Text("anchor").popover(item: .constant(Row(id: 1))) { row in Text("row \(row.id)") }
        #expect(form(view, horizontal: .regular) == .popover)
        #expect(form(view, horizontal: .compact) == .sheet)
    }

    // MARK: - Across a change of size class

    /// Counts its appearances: a presenting view that kept its place in the
    /// tree appears once, however the popover above it is presented.
    private struct Presenter: View {
        let classes: SizeClasses
        let isPresented: Binding<Bool>
        var body: some View {
            Text("anchor")
                .onAppear { classes.appearances += 1 }
                .popover(isPresented: isPresented) { Text("detail") }
                .environment(\.horizontalSizeClass, classes.horizontal)
        }
    }

    private struct Page: App {
        let classes: SizeClasses
        let isPresented: Binding<Bool>
        init() { self.init(classes: SizeClasses(), isPresented: .constant(false)) }
        init(classes: SizeClasses, isPresented: Binding<Bool>) { (self.classes, self.isPresented) = (classes, isPresented) }
        var body: some Scene { WindowGroup { Presenter(classes: classes, isPresented: isPresented) } }
    }

    private final class Flag: @unchecked Sendable {
        var value = true
    }

    @Test("The presenting view keeps its place when the size class changes, and Escape dismisses the sheet it became")
    func acrossAChange() {
        let (classes, flag) = (SizeClasses(), Flag())
        let isPresented = Binding(get: { flag.value }, set: { flag.value = $0 })
        let app = HeadlessApp(Page(classes: classes, isPresented: isPresented), width: 40, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        #expect(classes.appearances == 1)
        classes.horizontal = .compact
        frame()
        frame()
        #expect(classes.appearances == 1, "the presenting view was made anew when its popover became a sheet")
        #expect(app.screen.contains { $0.contains("detail") }, "the sheet is not drawn: \(app.screen)")
        app.send(KeyEvent(key: .escape))
        frame()
        #expect(flag.value == false, "Escape did not dismiss the sheet the popover became")
    }
}
