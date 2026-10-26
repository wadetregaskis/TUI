//  🖥️ TUI — A Terminal UI framework for Swift
//  LocaleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

//  The three values SwiftUI keeps apart for formatting — locale, calendar,
//  time zone — live together here because they are one family and are almost
//  always reasoned about together, not because any of them derives from the
//  others. A `Locale` carries a calendar and a `Calendar` carries a zone, and
//  SwiftUI still gives each its own key: they are three separate questions, and
//  an app that wants an Islamic calendar in a French UI showing UTC times has
//  to be able to say all three.

/// EnvironmentKey for the current locale.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct LocaleKey: EnvironmentKey {
    @usableFromInline static let defaultValue = Locale.autoupdatingCurrent
}

/// EnvironmentKey for the language a subtree's own strings are read in, where
/// its `\.locale` was set for it.
///
/// `@usableFromInline` for the `@inlinable` ``EnvironmentValues/locale`` setter,
/// which writes it.
@usableFromInline
struct StringLanguageKey: EnvironmentKey {
    @usableFromInline static let defaultValue: String? = nil
}

/// EnvironmentKey for the current calendar.
private struct CalendarKey: EnvironmentKey {
    static let defaultValue = Calendar.autoupdatingCurrent
}

/// EnvironmentKey for the current time zone.
private struct TimeZoneKey: EnvironmentKey {
    static let defaultValue = TimeZone.autoupdatingCurrent
}

extension EnvironmentValues {
    /// The locale for the view subtree.
    ///
    /// Matches SwiftUI's `\.locale`. It is populated each frame from the app's
    /// localization service (`applyRuntimeServices(from:)`), so by default it
    /// is the user's locale, as SwiftUI's is (`LocalizationService`'s
    /// `currentLocale`): their language and region, `pt_BR` under
    /// `LANG=pt_BR.UTF-8` whether or not TUI ships Portuguese, or, once the
    /// app chooses a language, that language with the user's region — `de`
    /// under `LANG=en_GB.UTF-8` writes dates as Britain orders them. Because
    /// it's a stored, settable key, a subtree can override it with
    /// `.environment(\.locale, _)` to format its numbers and dates in a
    /// different locale than the surrounding UI.
    ///
    /// `Table`, `List`, and `ScrollView`'s number chrome read it, so an override
    /// re-locales their formatted output.
    ///
    /// An override picks the language of the strings below it too, as
    /// SwiftUI's does (measured 2026-10-18): a `Text` made from a key reads it
    /// again, when it is drawn, in the language the locale names — the app's
    /// strings in that language, then TUI's, then English — so
    /// `ContentView().environment(\.locale, Locale(identifier: "de"))` shows
    /// the app's German strings. A locale whose language the app has no
    /// strings in reads English, as SwiftUI's development language does.
    @inlinable
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set {
            self[LocaleKey.self] = newValue
            self[StringLanguageKey.self] = newValue.language.languageCode?.identifier
        }
    }

    /// The language a subtree's own strings are read in, as a code, where its
    /// ``locale`` was set for it with `.environment(\.locale, _)`; `nil` where
    /// it was not, and strings are read in the app's language. Written by
    /// ``locale``'s setter; read by a `Text` made from a key when it draws.
    package var stringLanguage: String? {
        self[StringLanguageKey.self]
    }

    /// Publishes `locale` as the user's, at the root: what ``locale`` reads,
    /// with no language of a subtree's own (``stringLanguage``), since the
    /// app's strings are already read in the user's.
    package mutating func publishUserLocale(_ locale: Locale) {
        self[LocaleKey.self] = locale
    }

    /// The calendar for the view subtree — SwiftUI's `\.calendar`.
    ///
    /// The *calendrical system* date arithmetic happens in: which months a year
    /// has, how many days are in this one, when a year rolls over.
    /// ``DatePicker`` does all of its stepping and clamping through it, so
    /// overriding it changes what the field can hold, not merely how it reads.
    ///
    /// ```swift
    /// DatePicker("Date", selection: $date)
    ///     .environment(\.calendar, Calendar(identifier: .hebrew))
    /// ```
    ///
    /// Which ZONE that arithmetic happens in is ``EnvironmentValues/timeZone``,
    /// separately — see there for why the two are not one value.
    public var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }

    /// The time zone for the view subtree — SwiftUI's `\.timeZone`.
    ///
    /// A `Date` is an instant, not a date: which day and hour it *reads* as
    /// depends entirely on the zone. ``DatePicker`` shows and edits the
    /// components in this one, so an override moves the whole field — a value
    /// shown as 09:00 in Los Angeles is the same instant shown as 17:00 in UTC.
    ///
    /// ```swift
    /// DatePicker("UTC", selection: $timestamp)
    ///     .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    /// ```
    ///
    /// - Important: A `Calendar` carries a zone of its own, and where the two
    ///   disagree **this one wins**: `\.timeZone` is a statement *about* the
    ///   zone, while a calendar's is incidental to having chosen a calendrical
    ///   system. So set this one to change zones — building a `Calendar` with a
    ///   zone on it and setting only ``EnvironmentValues/calendar`` will not do
    ///   it.
    public var timeZone: TimeZone {
        get { self[TimeZoneKey.self] }
        set { self[TimeZoneKey.self] = newValue }
    }
}
