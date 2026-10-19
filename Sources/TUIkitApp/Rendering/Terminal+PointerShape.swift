//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+PointerShape.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension Terminal {
    /// Gives the pointer `shape`, or the terminal's own for `nil`, where this
    /// terminal takes a shape by name (``pointerShapeHost``): OSC 22 in its
    /// names, written only when it differs from what was last sent
    /// (``TerminalHostState``). Does nothing elsewhere, and nothing outside
    /// raw mode, when the shell has the terminal.
    ///
    /// A shape the host has no name for gives it its own pointer, rather than
    /// leaving whatever was there before.
    ///
    /// The first write since the last reset makes the reset owed
    /// (``TerminalHostSetting/isOwed``), and the debt a signal pays is armed
    /// with it before the write goes out, so no signal can find a shape set
    /// and nothing owed for it.
    func showPointerShape(_ shape: PointerShape?) {
        guard isRawMode, let host = pointerShapeHost, let setting = hostState.pointerShape else { return }
        let wanted = shape.flatMap(host.name(for:)).map(PointerShapeHost.sequence(naming:))
        guard let bytes = hostState.pointerShape?.update(to: wanted) else { return }
        if !setting.isOwed { armSignalRestore() }
        writeImmediate(bytes)
    }
}
