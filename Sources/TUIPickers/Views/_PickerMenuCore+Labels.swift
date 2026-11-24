//  🖥️ TUI — A Terminal UI framework for Swift
//  _PickerMenuCore+Labels.swift
//
//  A menu picker's option labels: rendered once a pass for the width every
//  measure and the closed draw read, and drawn only where they show (H-92).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _PickerMenuCore {
    /// Every option's label as a measure renders it, rendered once a pass at
    /// this place and handed to every measure and the draw after it
    /// (`composedOncePerPass`): what the width is found from. A closed picker
    /// of 500 options was measured three times a frame and drawn once, each
    /// rendering every label again (H-92, CTRLS-2). Always under a measuring
    /// context, whoever asks first, so the measure and the draw read the same
    /// lines whichever made them.
    ///
    /// Labels render at the SCREEN width, not the control's: the drop-down is an
    /// overlay that may grow wider than its control, so a narrow picker must not
    /// wrap or truncate its option labels.
    func measuredOptionLabels(context: RenderContext) -> [String?] {
        var labelContext = Self.optionLabelContext(in: context)
        labelContext.isMeasuring = true
        labelContext.hasExplicitWidth = false
        let render = { _PickerRenderedLabels(renderedLabels(in: labelContext)) }
        return (context.renderCache?.composedOncePerPass(for: self, context: labelContext, render) ?? render())
            .labels
    }

    /// The line each entry shows, rendered in `labelContext`.
    func renderedLabels(in labelContext: RenderContext) -> [String?] {
        entries.map { entry in
            // A section's title draws under the section-header chrome role,
            // as a `List`'s header and a menu's section title do.
            if case .title(let title) = entry {
                return title.renderToBuffer(context: sectionChromeContext(labelContext, .sectionHeader))
                    .lines.first ?? ""
            }
            return entry.label.map { $0.renderToBuffer(context: labelContext).lines.first ?? "" }
        }
    }

    /// The labels the draw shows: every option's drawn while the drop-down is
    /// open; while it is closed, the lines the measure found the width from,
    /// with only the option the control shows drawn — the one label on
    /// screen, and the only one whose draw anything sees.
    func shownOptionLabels(context: RenderContext, isOpen: Bool) -> [String?] {
        if isOpen { return renderedLabels(in: Self.optionLabelContext(in: context)) }
        var labels = measuredOptionLabels(context: context)
        if currentValueLabel == nil, !isMixed,
            let index = entries.firstIndex(where: { $0.tag == selection.wrappedValue }),
            let label = entries[index].label
        {
            labels[index] = label.renderToBuffer(context: Self.optionLabelContext(in: context)).lines.first ?? ""
        }
        return labels
    }
}

/// A picker's option labels as a measure rendered them, kept for the pass
/// (`RenderCache.composedOncePerPass(for:context:readsLayout:_:)` keeps an
/// object).
final class _PickerRenderedLabels {
    let labels: [String?]

    init(_ labels: [String?]) { self.labels = labels }
}
