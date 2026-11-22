//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyWriting.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

/// How the bar writes an item's key: a one-letter key as any key is drawn,
/// Shift as `⇧`, its letter in the ``KeyLetterCase`` in force, then in the
/// ``KeyNotation`` in force — read once from the environment for the whole
/// bar.
struct KeyWriting {
    let letterCase: KeyLetterCase
    let notation: KeyNotation

    init(_ environment: EnvironmentValues) {
        letterCase = environment.keyLetterCase
        notation = environment.keyNotation
    }

    /// `shortcut`, an item's key as its string writes it, as the bar draws it.
    func writing(_ shortcut: String) -> String {
        notation.spelling(letterCase.statusBarItemKey(shortcut))
    }
}
