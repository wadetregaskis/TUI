//  🖥️ TUI — A Terminal UI framework for Swift
//  DroppedMemberReports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import Foundation
import TUIFoundation

/// What `DroppedMember` reported while a test bound its reporter — a member a
/// container left out though SwiftUI shows it (owner ruling RC5), which a debug
/// build otherwise stops at.
///
/// ```swift
/// let reports = DroppedMemberReports()
/// let drawn = DroppedMember.$reporter.withValue(reports.record) { render(picker) }
/// #expect(reports.messages.isEmpty)
/// ```
final class DroppedMemberReports: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    /// The reports, oldest first.
    var messages: [String] { lock.withLock { recorded } }

    /// The reporter to bind.
    var record: @Sendable (String) -> Void {
        { [self] message in lock.withLock { recorded.append(message) } }
    }
}

#endif
