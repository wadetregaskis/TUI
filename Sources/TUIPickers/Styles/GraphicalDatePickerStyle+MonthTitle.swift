//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicalDatePickerStyle+MonthTitle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A month's name and year as the graphical date picker's header spells it —
/// `October 2026` — in the calendar's own locale, time zone and era: the
/// `MMMMyyyy` template through a `DateFormatter`.
///
/// Memoised, because configuring that formatter is the dear part, and a picker
/// on screen asked for it every frame (2026-10-26: `-[NSDateFormatter
/// setLocalizedDateFormatFromTemplate:]` 5.3% and `_regenerateFormatter` 5.1%
/// of a frame of the Stress `pickers` scenario, for one string that changes when
/// the month does). Not `Date.FormatStyle`, which caches its own formatter: it
/// spells a different string for 12,002 of 15,510 locale, calendar and date
/// combinations measured that night — an era before a Japanese, Buddhist,
/// Islamic or Hebrew year, among others.
///
/// A static, and not a singleton in the sense of the project's "No Singletons"
/// rule: a private, bounded memo of a pure function, keyed by everything the
/// function reads — the month, and the identifiers of the calendar, its time
/// zone and the locale it is spelled in — so nothing outside it can tell a hit
/// from a miss. Identifiers, not the values: an autoupdating calendar, zone or
/// locale compares equal to itself after the system's setting has changed.
/// Rebuilt from them, the formatter spells what the caller's own calendar and
/// locale spell: identical for all 18,648 locale, calendar and date
/// combinations measured on 2026-10-26. The ASCII palette's search index is the precedent
/// (`ASCIIPalette+SearchIndex.swift`).
enum CalendarMonthTitle {
    static func title(of month: Date, calendar: Calendar, locale: Locale) -> String {
        store.title(
            Key(
                month: month, calendar: calendar.identifier, timeZone: calendar.timeZone.identifier,
                locale: locale.identifier))
    }

    private struct Key: Hashable {
        let month: Date
        let calendar: Calendar.Identifier
        let timeZone: String
        let locale: String
    }

    private static let store = Store()

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var titles: [Key: String] = [:]
        private var order: [Key] = []
        private let capacity = 16

        func title(_ key: Key) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let title = titles[key] { return title }
            let formatter = DateFormatter()
            var calendar = Calendar(identifier: key.calendar)
            calendar.timeZone = TimeZone(identifier: key.timeZone) ?? calendar.timeZone
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: key.locale)
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            let title = formatter.string(from: key.month)
            titles[key] = title
            order.append(key)
            if order.count > capacity {
                titles.removeValue(forKey: order.removeFirst())
            }
            return title
        }
    }
}
