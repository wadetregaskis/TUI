//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetDockReadersTests.swift
//
//  A sheet's presenter posts the rows it docks only to a focus manager that a
//  root lays the page out by. The resolver it posts holds the presenter's
//  environment, and the environment holds the manager the resolver was posted
//  to: a post that no root reads was never replaced, and the two kept each
//  other alive, with everything the environment reached.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport
@testable import TUIView

/// Every focus manager the rows were drawn under, held weakly.
@MainActor
private final class ManagerWitness {
    private final class Box {
        weak var manager: FocusManager?
        init(_ manager: FocusManager) { self.manager = manager }
    }

    /// The managers other than this one: the probe's.
    weak var live: FocusManager?
    private var probed: [Box] = []

    func note(_ manager: FocusManager) {
        if manager !== live { probed.append(Box(manager)) }
    }

    /// How many rows were drawn under a manager other than the live one.
    var probedCount: Int { probed.count }

    /// How many of those managers are still alive.
    var probedAlive: Int { probed.count { $0.manager != nil } }
}

/// A row that notes the manager it is drawn under.
private struct WitnessRow: View, Renderable {
    let index: Int
    let witness: ManagerWitness

    var body: Never { fatalError("WitnessRow renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring, let manager = context.environment.focusManager { witness.note(manager) }
        return FrameBuffer(lines: ["row \(index)"])
    }
}

@MainActor
@Suite("Where a sheet posts its dock")
struct SheetDockReadersTests {
    private static let viewportHeight = 6

    /// One frame of a windowed lazy stack, as the run loop draws it, with a
    /// focus manager that no root reads — the focus-reach probe's own, and a
    /// test host's.
    private func frame(_ view: some View, tuiContext: TUIContext, focusManager: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(offset: 0, viewportHeight: Self.viewportHeight)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 200, environment: environment, tuiContext: tuiContext)
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    /// The windowed stack draws each row past the focused one under a
    /// scratch focus manager of its own until one registers a focusable
    /// (`_VStackCore.focusRingContinuations`). Each row here holds a
    /// dismissed sheet, which posted its dock to that scratch manager: the
    /// resolver held the probe's environment, which held the scratch manager,
    /// and nothing read or replaced the post — every probed row's manager
    /// outlived the frame, every frame.
    @Test("The focus-reach probe's managers go with the frame, past rows that hold a sheet")
    func probeManagersGoWithTheFrame() {
        let witness = ManagerWitness()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { index in
                if index == 0 {
                    Button("first") {}
                } else {
                    WitnessRow(index: index, witness: witness)
                        .sheet(isPresented: .constant(false)) { Text("sheet") }
                }
            }
        }
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        witness.live = focusManager
        // The first frame focuses the button; the probe walks from it on the
        // second.
        frame(view, tuiContext: tuiContext, focusManager: focusManager)
        frame(view, tuiContext: tuiContext, focusManager: focusManager)

        #expect(witness.probedCount >= 19, "precondition: the probe walked the rows past the button")
        #expect(witness.probedAlive == 0, "\(witness.probedAlive) probe managers outlived their frame")
    }

    /// The rule the probe's managers fall under, asked of the ledger: a
    /// manager that no root has asked for docks takes none.
    @Test("A dismissed sheet drawn where no root reads docks posts none")
    func noRootNoPost() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = Text("page").sheet(isPresented: .constant(false)) { Text("sheet") }
        frame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(focusManager.postedDocks.isEmpty)

        _ = focusManager.presentationDock(in: 20, storage: tuiContext.stateStorage)
        frame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(focusManager.postedDocks.count == 1, "a root asked, and the sheet posted nothing")
        focusManager.forgetPresentationDocks()
    }

    /// A dismissed sheet posts so that one presented between two frames
    /// docks on its first. Two never can: an `item:` sheet's content is made
    /// from the item read while it was dismissed, which is none, and a closed
    /// popover's sheet form is presented by a binding that holds the form
    /// read while it was closed. Each posted every frame all the same.
    @Test("A dismissed item: sheet and a closed popover post no dock, which could never dock")
    func postsOnlyWhatCouldDock() {
        struct Note: Identifiable { let id: Int }
        let item = Binding<Note?>.constant(nil)
        let views: [(String, AnyView)] = [
            ("item: sheet", AnyView(Text("page").sheet(item: item) { _ in Text("sheet") })),
            ("popover", AnyView(Text("page").popover(isPresented: .constant(false)) { Text("popover") })),
        ]
        for (name, view) in views {
            let tuiContext = TUIContext()
            let focusManager = FocusManager()
            _ = focusManager.presentationDock(in: 20, storage: tuiContext.stateStorage)
            frame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(focusManager.postedDocks.isEmpty, "the \(name) posted a dock")
            focusManager.forgetPresentationDocks()
        }
    }
}
