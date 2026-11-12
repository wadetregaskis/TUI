//  🖥️ TUI — A Terminal UI framework for Swift
//  TabViewClicks.swift
//
//  A tab view's strip as the pointer reaches it: a click handler on each
//  tab's chip, which selects its tab and focuses the strip.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension _TabViewCore {
    func persistedFocusIDForClicks(_ context: RenderContext) -> String {
        FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: TabViewStateIndex.focusID)
    }

    /// Registers a click handler per tab region (selecting that tab).
    @MainActor
    func attachTabClicks(
        to buffer: inout FrameBuffer,
        regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher else { return }
        let captureFocusID = persistedFocusIDForClicks(context)
        let focusManager = context.environment.focusManager
        // A tab is a click target, so it answers the pointer like one.
        dispatcher.requestFeature(.motion, in: context)
        let hoverBox = hoveredTabBox(context: context)
        for region in regions {
            let value = tabs[region.index].value
            let isDisabledTab = tabs[region.index].isDisabled
            let capture = selection
            let index = region.index
            let handlerID = dispatcher.register(in: context) { event in
                if let lifted = Self.hover(event, overTab: index, hoverBox: hoverBox) { return lifted }
                guard event.phase == .released, event.button == .left else {
                    return event.phase == .pressed && event.button == .left
                }
                focusManager?.focus(id: captureFocusID)
                // A disabled tab takes the click and selects nothing.
                if !isDisabledTab, let v = value.base as? SelectionValue { capture.wrappedValue = v }
                return true
            }
            // A click: a release off the tab selects nothing (decisions B89).
            dispatcher.fileClickRecognizer(.plain, for: handlerID, in: context)
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: region.x, offsetY: region.y, width: region.width, height: region.height,
                    handlerID: handlerID, focusID: nil))
            // A drag held still over the chip selects its tab, as the click
            // above does.
            registerSpringLoading(forTab: region.index, handlerID: handlerID, context: context)
        }
        // Each chip's own context menu, popovers, drag and drops, in front of
        // the click regions above.
        attachTabInteractions(to: &buffer, regions: regions, context: context)
    }
}
