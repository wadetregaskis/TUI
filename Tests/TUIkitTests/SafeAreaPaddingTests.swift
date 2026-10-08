//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SafeAreaPaddingTests.swift
//
//  `safeAreaPadding`: padding for ordinary content, and for a scroll view a
//  content margin along the axes it scrolls (decisions B6; SwiftUI's geometry
//  measured on macOS 15).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitView

@MainActor
@Suite("safeAreaPadding")
struct SafeAreaPaddingTests {

    private func lines<V: View>(_ view: V, width: Int = 16, height: Int = 6) -> [String] {
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: EnvironmentValues(), tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, width: Int = 16, height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    private func rows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { Text("row \($0)") }
        }
    }

    @Test("On ordinary content it is padding")
    func ordinaryContentIsPadded() {
        #expect(lines(Text("x").safeAreaPadding(2)) == lines(Text("x").padding(2)))
        #expect(lines(Text("x").safeAreaPadding(.leading, 3)) == lines(Text("x").padding(.leading, 3)))
        // nil is the default padding: one cell, as 16 points is to SwiftUI's.
        #expect(lines(Text("x").safeAreaPadding()) == lines(Text("x").padding()))
        // A List is not a ScrollView here, and is padded whole.
        #expect(
            lines(List { Text("a") }.safeAreaPadding(.top, 1))
                == lines(List { Text("a") }.padding(.top, 1)))
    }

    @Test("Along a scroll view's axis it is a content margin, which scrolls away")
    func scrollAxisIsAMargin() {
        let frames = Frames()
        let view = ScrollView { rows(20) }.scrollIndicators(.hidden).safeAreaPadding(.vertical, 1)
        let top = frames.render(view)
        #expect(top[0].trimmingCharacters(in: .whitespaces).isEmpty, "\(top)")
        #expect(top[1].hasPrefix("row 0"), "\(top)")
        frames.handler?.userScrollFine(by: 1)
        let scrolled = frames.render(view)
        #expect(scrolled[0].hasPrefix("row 0"), "padding would have stayed: \(scrolled)")
    }

    @Test("Across a scroll view's axis it is padding, which takes the bar in with the view")
    func crossAxisIsPadding() {
        #expect(
            lines(ScrollView { rows(20) }.safeAreaPadding(.horizontal, 2))
                == lines(ScrollView { rows(20) }.padding(.horizontal, 2)))
    }

    @Test("Behind a geometry change the scroll view is ordinary content")
    func behindPaddingItIsPadding() {
        #expect(
            lines(ScrollView { rows(20) }.padding(1).safeAreaPadding(.vertical, 1))
                == lines(ScrollView { rows(20) }.padding(1).padding(.vertical, 1)))
    }

    @Test("Nested calls add up, and add to content margins")
    func nestedAndMarginsAdd() {
        let view = ScrollView { rows(20) }
            .scrollIndicators(.hidden)
            .contentMargins(.top, 1)
            .safeAreaPadding(.top, 1)
            .safeAreaPadding(.top, 1)
        let drawn = lines(view)
        #expect(drawn[0...2].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(drawn)")
        #expect(drawn[3].hasPrefix("row 0"), "\(drawn)")
    }

    @Test("A scroll view in the content does not inherit it")
    func nestedScrollViewDoesNotInherit() {
        let drawn = lines(
            ScrollView(.horizontal) {
                ScrollView { Text("inner") }.scrollIndicators(.hidden).frame(width: 8, height: 1)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.leading, 2),
            height: 3)
        #expect(drawn[0].hasPrefix("  inner"), "\(drawn)")
    }
}
