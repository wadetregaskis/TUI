//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetContentBuildTests.swift
//
//  A sheet's or a cover's content closure runs only while the presentation
//  is presented — once in each frame it is drawn — as SwiftUI's does: never
//  while it is dismissed, so a page that holds a sheet does not build its
//  content on every frame, and what the content is made from is read when it
//  is presented, not when the page first drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
import TUIChrome
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A presentation builds its content only while it is presented")
struct SheetContentBuildTests {
    private struct Note: Identifiable {
        let id: Int
    }

    /// The page's state, by reference so every frame's bindings reach it.
    @MainActor
    private final class Model {
        var presented = false
        var note: Note?
        /// How many times a content closure ran.
        var builds = 0
        /// What a request is made from, and the request once made: kept
        /// until the presentation ends, as a file panel keeps its own.
        var source = "first"
        var request: String?
        var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
        var noteBinding: Binding<Note?> { Binding(get: { self.note }, set: { self.note = $0 }) }

        func draft() -> some View {
            builds += 1
            return Text("draft")
        }

        func madeRequest() -> String {
            if let request { return request }
            request = source
            return source
        }
    }

    private func harness() -> InputChainHarness {
        InputChainHarness(width: 60, height: 20) { environment in
            environment.terminalWidth = 60
            environment.terminalHeight = 20
            environment.overlayContentHeight = 20
        }
    }

    /// The builds three frames dismissed, two presented and two dismissed
    /// again come to, presenting and dismissing with `toggle`.
    private func buildsAcross(
        _ model: Model, page: () -> some View, toggle: (Bool) -> Void
    ) -> (dismissed: Int, presented: Int, dismissedAgain: Int) {
        let harness = harness()
        for _ in 0..<3 { harness.frame(page()) }
        let dismissed = model.builds
        toggle(true)
        for _ in 0..<2 { harness.frame(page()) }
        let presented = model.builds
        toggle(false)
        for _ in 0..<2 { harness.frame(page()) }
        return (dismissed, presented, model.builds)
    }

    @Test("A sheet's content is built only in the frames it is presented, once in each")
    func sheet() {
        let model = Model()
        let builds = buildsAcross(model, page: {
            Text("page").sheet(isPresented: model.binding) { model.draft() }
        }, toggle: { model.presented = $0 })
        #expect(builds.dismissed == 0, "a dismissed sheet built its content")
        #expect(builds.presented == 2, "two presented frames built it \(builds.presented) times")
        #expect(builds.dismissedAgain == 2, "the dismissed sheet built its content again")
    }

    @Test("A full-screen cover's content is built only in the frames it is presented")
    func cover() {
        let model = Model()
        let builds = buildsAcross(model, page: {
            Text("page").fullScreenCover(isPresented: model.binding) { model.draft() }
        }, toggle: { model.presented = $0 })
        #expect(builds.dismissed == 0)
        #expect(builds.presented == 2)
        #expect(builds.dismissedAgain == 2)
    }

    @Test("An item sheet's content is built only in the frames it is presented")
    func itemSheet() {
        let model = Model()
        let builds = buildsAcross(model, page: {
            Text("page").sheet(item: model.noteBinding) { _ in model.draft() }
        }, toggle: { model.note = $0 ? Note(id: 1) : nil })
        #expect(builds.dismissed == 0)
        #expect(builds.presented == 2)
        #expect(builds.dismissedAgain == 2)
    }

    @Test("A popover's content is built only in the frames it is presented")
    func popover() {
        let model = Model()
        let builds = buildsAcross(model, page: {
            Text("page").popover(isPresented: model.binding) { model.draft() }
        }, toggle: { model.presented = $0 })
        #expect(builds.dismissed == 0, "a closed popover built its content")
        #expect(builds.presented == 2, "two presented frames built it \(builds.presented) times")
        #expect(builds.dismissedAgain == 2, "the closed popover built its content again")
    }

    @Test("What a sheet's content is made from is read when it is presented, not when the page first drew")
    func madeWhenPresented() {
        let model = Model()
        let harness = harness()
        let page = {
            Text("page").sheet(isPresented: model.binding) { Text("request: \(model.madeRequest())") }
        }
        harness.frame(page())
        model.source = "second"
        model.presented = true
        let screen = harness.frame(page())
            .compositingOverlays(maxWidth: 60, maxHeight: 20, palette: harness.context.environment.palette)
            .lines.map(\.stripped).joined(separator: "\n")
        #expect(screen.contains("request: second"), "the content was made on the page's first frame: \(screen)")
    }
}
