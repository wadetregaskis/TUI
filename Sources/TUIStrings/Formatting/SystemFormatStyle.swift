//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemFormatStyle.swift
//
//  SwiftUI's `SystemFormatStyle`: the timer, stopwatch, offset and reference
//  formats its live text uses, as Foundation `DiscreteFormatStyle`s — each
//  knows the next instant its output changes, which is what lets a
//  `Text(.currentDate, format:)` ask for a frame only then.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A namespace for format styles that implement designs used across Apple's
/// platforms — mirrors SwiftUI's `SystemFormatStyle`.
///
/// Each style formats a `Date` — usually now — into an `AttributedString`,
/// and is a `DiscreteFormatStyle`, so it can say when its output next changes:
///
/// ```swift
/// Text(.currentDate, format: .timer(countingDownIn: start..<end))
/// Text(.currentDate, format: .stopwatch(startingAt: start))
/// Text(.currentDate, format: .offset(to: deadline))
/// Text(.currentDate, format: .reference(to: meeting))
/// ```
///
/// The outputs carry no attributes: a terminal draws the characters. Their
/// strings are SwiftUI's, measured on macOS 15 and pinned in the
/// `SystemFormatStyle…Tests` suites.
public enum SystemFormatStyle: Sendable {}

extension SystemFormatStyle {
    /// The instant a reading changes, from the VALUE it changes at and how the
    /// value maps to time.
    ///
    /// A change just past a value, in the direction the value travels, is just
    /// after that value's instant going forward in time and just before it
    /// going back — whichever way the value runs with time.
    static func instant(of boundary: ClockFace.Boundary, at time: (Double) -> Date, forward: Bool) -> Date {
        switch boundary {
        case .at(let value):
            return time(value)
        case .justPast(let value):
            return forward ? time(value).justAfter : time(value).justBefore
        }
    }
}
