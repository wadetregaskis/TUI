//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppTerminationPreventing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The sheet's trait

/// Content that has said whether its presentation stops the app being quit.
@MainActor
package protocol AppTerminationPreventing {
    /// `true` to stop the quit key while presented, `false` to allow it, `nil`
    /// for the automatic behaviour.
    var preventsAppTermination: Bool? { get }
}

/// Whether a presentation of `content` stops the app being quit: SwiftUI's
/// rule for several statements, where a non-`nil` one overrides `nil` and
/// `true` takes precedence over `false`, and the automatic `nil` does not.
@MainActor
package func presentationPreventsTermination(of content: any View) -> Bool {
    presentationTraits(AppTerminationPreventing.self, of: content)
        .contains { $0.preventsAppTermination == true }
}
