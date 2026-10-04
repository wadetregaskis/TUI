//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Live.swift
//
//  A `Text` whose words are a function of the clock — a relative date, a
//  timer, a live format — formatted when it is drawn rather than when it is
//  built, which asks the run loop for one frame at the instant its words next
//  change and for nothing in between.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitView

// MARK: - Sources

/// What a live `Text` reads: its words at any instant, and when they change.
///
/// A source is a value — two `Text(date, style: .relative)`s built from the
/// same date are equal — and it knows its own next change, which is what lets
/// a "2 minutes ago" ask for a frame once a minute rather than sixty a second.
protocol LiveTextSource: Sendable {
    /// The words at `date`.
    func text(at date: Date, in environment: LiveTextEnvironment) -> String

    /// The first instant after `date` at which ``text(at:in:)`` reads
    /// differently, or `nil` when it never will again — a finished timer, a
    /// fixed date's time of day.
    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date?

    /// Whether `other` is a source of the same type holding the same values.
    func isEqual(to other: any LiveTextSource) -> Bool
}

extension LiveTextSource where Self: Equatable {
    func isEqual(to other: any LiveTextSource) -> Bool {
        (other as? Self) == self
    }
}

/// The three environment values a live text formats with: SwiftUI's
/// `\.locale`, `\.calendar` and `\.timeZone`, the zone set on the calendar —
/// the environment's zone wins over the calendar's own, as everywhere else.
struct LiveTextEnvironment: Sendable {
    var locale: Locale
    var calendar: Calendar

    init(locale: Locale, calendar: Calendar, timeZone: TimeZone) {
        self.locale = locale
        self.calendar = calendar
        self.calendar.timeZone = timeZone
        self.calendar.locale = locale
    }

    /// The environment a view is being drawn in.
    init(_ environment: EnvironmentValues) {
        self.init(locale: environment.locale, calendar: environment.calendar, timeZone: environment.timeZone)
    }

    /// The process's own settings, for a text read before anything draws it.
    static var current: Self {
        Self(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)
    }
}

/// A source, boxed so a ``Text/Run`` holds one pointer to it.
///
/// Equal by the source's values, not by identity, so two texts built from the
/// same date compare equal however often their view was rebuilt. Every box
/// hashes alike, which is consistent with that equality and costs nothing:
/// nothing hashes enough live texts for the collisions to matter.
final class LiveTextBox: Sendable, Hashable {
    let source: any LiveTextSource

    init(_ source: any LiveTextSource) {
        self.source = source
    }

    static func == (lhs: LiveTextBox, rhs: LiveTextBox) -> Bool {
        lhs === rhs || lhs.source.isEqual(to: rhs.source)
    }

    func hash(into hasher: inout Hasher) {}
}

// MARK: - Building a live text

extension Text {
    /// A text reading `source`, one run long.
    ///
    /// Its stored ``content`` is the source read once now, in the process's own
    /// locale: what anything that takes a `Text` for its string — a navigation
    /// title, a help tag — gets, since those have no frame to draw it in. The
    /// render reads the source again at the frame's own date.
    init(live source: some LiveTextSource) {
        let now = source.text(at: Date(), in: .current)
        self.init(verbatim: now)
        runs = [Run(text: now, style: TextStyle(), live: LiveTextBox(source))]
    }

    /// Whether any run of this text reads the clock.
    nonisolated var isLive: Bool {
        runs?.contains { $0.live != nil } ?? false
    }

    /// This text as it reads at `date`, with every live run's words filled in
    /// and nothing live left; and the earliest instant any of them changes.
    ///
    /// `nil` when nothing in the text is live. A text that is one live run with
    /// no style of its own comes back as a plain text — no runs at all — so it
    /// takes exactly the path, and makes exactly the bytes, of a `Text` built
    /// from the same string.
    func readingLive(at date: Date, in environment: LiveTextEnvironment) -> (text: Text, next: Date?)? {
        guard let runs, runs.contains(where: { $0.live != nil }) else { return nil }
        var next: Date?
        let read = runs.map { run -> Run in
            guard let live = run.live else { return run }
            if let change = live.source.nextChange(after: date, in: environment) {
                next = min(next ?? change, change)
            }
            return Run(text: live.source.text(at: date, in: environment), style: run.style)
        }
        var text = Text(verbatim: read.map(\.text).joined())
        text.style = style
        if read.count > 1 || read.first?.style != TextStyle() {
            text.runs = read
        }
        return (text, next)
    }

    /// This text as it reads at the frame being drawn, having told the run loop
    /// when it next changes; `nil` when nothing in it is live.
    ///
    /// The date is the FRAME's (`RenderCache.frameDate`), not the clock at each
    /// read, so the measure and the render of one frame read the same words —
    /// see `TimelineView`, whose reasons these are.
    ///
    /// What is declared is `TimelineView`'s pair, for the same reasons:
    ///
    /// - A render asks for one wake, at the next change. The request also
    ///   tells every value memo above that this subtree changes with time, so
    ///   none of them keeps its buffer.
    /// - A measure asks for nothing (a wake is a render's side effect) but
    ///   records a read of the clock that moves at the next change, so a size
    ///   memo above keeps this text's width no longer than that — and the two
    ///   that keep one width for a whole collection keep it exactly that long.
    ///
    /// A text with no next change — a finished timer, a time of day — declares
    /// nothing, and memoises like any other.
    func readingLive(declaringIn context: RenderContext, measuring: Bool) -> Text? {
        // Asked before the environment is copied out: building the calendar
        // with the environment's zone on it allocates, and a concatenation
        // with nothing live must not pay for that on every frame.
        guard isLive else { return nil }
        let date = context.renderCache?.frameDate ?? Date()
        guard let (text, next) = readingLive(at: date, in: LiveTextEnvironment(context.environment)) else {
            return nil
        }
        guard let next else { return text }
        if measuring || context.isMeasuring {
            context.environment.volatileReadTracker?.recordClockedRead(movingAt: next)
        }
        guard !measuring else { return text }
        // A millisecond past the change: the wake is timed on the monotonic
        // clock and the words are read from the wall clock, and a wake that
        // lands a hair early reads the old words and has to ask again. (A
        // render under `isMeasuring` asks for nothing; `requestWake` sees to
        // that.)
        context.requestWake(
            token: "text-\(context.identity.path)", afterSeconds: next.timeIntervalSince(date) + 0.001)
        return text
    }
}
