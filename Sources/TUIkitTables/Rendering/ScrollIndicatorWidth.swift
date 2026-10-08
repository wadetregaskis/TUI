//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollIndicatorWidth.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// The width an indicator line draws, without drawing it — for `Table`'s measure,
/// which used to render the whole line to read its `strippedLength`: a colour
/// chosen, and spelled for the emitter, in a pass that draws nothing.
func scrollIndicatorWidth(
    direction: ScrollIndicatorDirection, count: Int, unit: ScrollIndicatorUnit,
    width: Int, approximate: Bool = false, locale: Locale = .current
) -> Int {
    scrollIndicatorParts(
        direction: direction, count: count, unit: unit, width: width,
        approximate: approximate, locale: locale
    ).width
}
