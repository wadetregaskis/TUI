//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+ContentType.swift
//
//  `.textContentType(_:)` in a TextEditor: what is typed or pasted is
//  filtered as a TextField filters it, and the bell rings for what is turned
//  away.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension TextEditorHandler {
    /// `event` as the content type lets it through: a typed character, a
    /// space, a line break or a tab it turns away is consumed with a ring of
    /// the bell (`nil`), and a paste loses what it turns away, the bell ringing
    /// once for whatever went. Every other key passes as it is, as does
    /// everything with no content type.
    ///
    /// A line break is filtered as any character is, as a vertical text field
    /// filters it: an editor whose content is an email address takes none.
    func admitted(_ event: KeyEvent) -> KeyEvent? {
        guard let contentType = textContentType else { return event }
        let inserted: Character
        switch event.key {
        case .character(let character) where !event.ctrl && !event.alt: inserted = character
        case .space: inserted = " "
        case .enter: inserted = "\n"
        case .tab where event.alt: inserted = "\t"
        case .paste(let string):
            guard let kept = admitted(string) else { return nil }
            guard kept.count != string.count else { return event }
            return KeyEvent(
                key: .paste(kept), ctrl: event.ctrl, alt: event.alt, shift: event.shift, phase: event.phase,
                capsLock: event.capsLock, numericPad: event.numericPad, pasteAttachments: event.pasteAttachments)
        default: return event
        }
        guard contentType.isAllowed(inserted) else {
            bell?.ring()
            return nil
        }
        return event
    }

    /// `string` with what the content type turns away taken out, the bell
    /// ringing once if anything was; `nil` where nothing is left of a string
    /// that had something in it, so the caller leaves the selection be, as a
    /// field does.
    func admitted(_ string: String) -> String? {
        guard let contentType = textContentType else { return string }
        let kept = contentType.filterString(string)
        if kept.count != string.count { bell?.ring() }
        return kept.isEmpty && !string.isEmpty ? nil : kept
    }
}
