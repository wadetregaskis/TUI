//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTargetTestSupport.swift
//
//  What the scroll target behaviour suites share: a harness that renders
//  frames and drives the wheel and keys, and a marked stack of numbered rows.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Renders frames of one view, and drives its wheel and keys: the harness of
/// the scroll target behaviour suites.
@MainActor
final class ScrollTargetFrames {
    let tui = TUIContext()
    let focusManager = FocusManager()
    var last = FrameBuffer()
    var width: Int
    var height: Int

    init(width: Int = 30, height: Int = 10) {
        self.width = width
        self.height = height
    }

    @discardableResult
    func render<V: View>(_ view: V) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.horizontalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        last = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        tui.mouseEventDispatcher.setRegions(last.hitTestRegions)
        return last
    }

    /// One wheel tick over the middle of the view.
    func wheel(_ button: MouseButton) {
        tui.mouseEventDispatcher.setActiveSupport(.standard)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: button, phase: .scrolled, x: width / 2, y: height / 2))
    }

    var scrollView: ScrollViewHandler? {
        focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
    }

    /// The first row number drawn on the frame's first line that has one.
    var topRow: Int? {
        for line in last.lines {
            let text = line.stripped
            if let marker = text.range(of: "row ") {
                return Int(text[marker.upperBound...].prefix { $0.isNumber })
            }
        }
        return nil
    }
}

/// A stack of `count` rows marked with `scrollTargetLayout()`, lazy unless
/// asked otherwise, each `height` lines tall with its number on its first line.
@MainActor
func scrollTargetRows(_ count: Int, height: @escaping (Int) -> Int = { _ in 1 }, lazy: Bool = true) -> AnyView {
    let rows = ForEach(0..<count, id: \.self) { index in
        Text("row \(index)").frame(height: height(index), alignment: .top)
    }
    return lazy
        ? AnyView(LazyVStack(alignment: .leading, spacing: 0) { rows }.scrollTargetLayout())
        : AnyView(VStack(alignment: .leading, spacing: 0) { rows }.scrollTargetLayout())
}
