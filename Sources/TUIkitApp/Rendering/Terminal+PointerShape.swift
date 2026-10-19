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
    func showPointerShape(_ shape: PointerShape?) {
        guard isRawMode, let host = pointerShapeHost, hostState.pointerShape != nil else { return }
        let wanted = shape.flatMap(host.name(for:)).map(PointerShapeHost.sequence(naming:))
        guard let bytes = hostState.pointerShape?.update(to: wanted) else { return }
        writeImmediate(bytes)
    }
}
