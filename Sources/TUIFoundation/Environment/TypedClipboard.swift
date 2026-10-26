//  🖥️ TUI — A Terminal UI framework for Swift
//  TypedClipboard.swift
//
//  The values behind the clipboard's text: what lets a value copied in this
//  app be pasted back into it as itself, when a terminal's clipboard holds
//  only text.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The values a copy or cut last put on the clipboard, and the text the
/// clipboard got for them.
///
/// SwiftUI moves `Transferable` values through the system pasteboard, which
/// holds each in every representation it offers. A terminal's clipboard holds
/// one string. So a copy writes its values' text there and keeps the values
/// here; a paste that finds the same text on the clipboard takes the values,
/// and one that finds other text — copied elsewhere since — reads that text.
package final class TypedClipboard: @unchecked Sendable {
    // Touched only from the main actor (commands run from key handlers there);
    // `@unchecked` because it travels in the environment, which is `Sendable`.
    private var values: [Any] = []
    private var text: String?

    /// Records `values`, copied as `text`.
    func store(_ values: [Any], as text: String) {
        self.values = values
        self.text = text
    }

    /// The values last copied, as `T`, if the clipboard still holds the text
    /// they were copied as and every one of them is a `T`.
    func values<T>(as type: T.Type, ifClipboardHolds current: String) -> [T]? {
        guard current == text else { return nil }
        let typed = values.compactMap { $0 as? T }
        return typed.count == values.count && !typed.isEmpty ? typed : nil
    }
}

/// How values cross a terminal's clipboard: as text, both ways.
enum ClipboardText {
    /// The text a value is copied as: a string itself, or a value's lossless
    /// or plain description, or `nil` for a value with neither.
    static func text(of value: Any) -> String? {
        if let string = value as? String { return string }
        if let lossless = value as? any LosslessStringConvertible { return lossless.description }
        if let described = value as? any CustomStringConvertible { return described.description }
        return nil
    }

    /// The text of `values`, one per line, or `nil` when none has any.
    static func text(of values: [Any]) -> String? {
        let lines = values.compactMap(text(of:))
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// `text` read as `T`: the string for `String`, one value parsed from it
    /// for a `LosslessStringConvertible` type, and `nil` for anything else.
    static func values<T>(_ text: String, as type: T.Type) -> [T]? {
        if let string = text as? T { return [string] }
        if let parsing = T.self as? any LosslessStringConvertible.Type,
            let value = parsing.init(text) as? T
        {
            return [value]
        }
        return nil
    }

    /// What a paste of `text` gives as `T`: the values this app copied, if
    /// that is what the clipboard still holds, or the text read as `T`.
    static func pasted<T>(_ text: String, as type: T.Type, from clipboard: TypedClipboard?) -> [T]? {
        clipboard?.values(as: T.self, ifClipboardHolds: text) ?? values(text, as: T.self)
    }
}

extension ClipboardAccess {
    /// Copies `values`: their text onto the clipboard, and the values beside
    /// it where the app keeps them.
    func copy(_ values: [Any]) {
        guard let text = ClipboardText.text(of: values) else { return }
        write(text)
        typed?.store(values, as: text)
    }

    /// What a paste of `text` gives as `T`, or `nil` if it cannot be had as
    /// one — see ``ClipboardText/pasted(_:as:from:)``.
    func paste<T>(_ text: String, as type: T.Type) -> [T]? {
        ClipboardText.pasted(text, as: T.self, from: typed)
    }
}
