//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationBackgroundProviding.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The trait

/// Content that has named its presentation's background.
@MainActor
package protocol PresentationBackgroundProviding {
    /// `view`, with the background behind it.
    func presentationBackground<V: View>(behind view: V) -> AnyView
}

/// `view` with the background `content` named for its presentation, if it
/// named one.
@MainActor
func withPresentationBackground<V: View>(_ view: V, from content: any View) -> AnyView? {
    presentationTrait(PresentationBackgroundProviding.self, of: content)?
        .presentationBackground(behind: view)
}
