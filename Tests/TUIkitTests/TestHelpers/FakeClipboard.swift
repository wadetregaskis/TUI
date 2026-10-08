//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FakeClipboard.swift
//
//  A clipboard a text control can be handed in place of the system one, so a
//  test sees what it would have copied and chooses what a paste reads, without
//  touching the developer's pasteboard or racing the rest of the suite over it
//  (see `ClipboardAccess`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit
@testable import TUIkitFoundation

/// Records what a text control hands the clipboard, and answers reads from the
/// same store. One per control under test, so tests run in parallel with
/// everything else without a shared pasteboard to race over.
final class FakeClipboard: @unchecked Sendable {
    /// What a paste reads: the last write, or what the test put there.
    var contents: String?
    /// Every write, in order.
    var writes: [String] = []

    init(contents: String? = nil) {
        self.contents = contents
    }

    /// The access to hand a control, as its `clipboard`. Every write is a
    /// plain success.
    var access: ClipboardAccess {
        ClipboardAccess(
            put: { [self] text, _ in
                writes.append(text)
                contents = text
                return .copied
            },
            read: { [self] in contents }
        )
    }
}
