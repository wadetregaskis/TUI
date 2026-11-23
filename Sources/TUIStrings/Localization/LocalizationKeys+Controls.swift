//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationKeys+Controls.swift
//
//  The keys of words TUI's own controls draw that an app has no public key
//  for: internal to the package, as the file panel's are.
//
//  Created by Wade Tregaskis
//  License: MIT

extension LocalizationKey {
    /// What an image draws while it has no picture: the line a failed load
    /// shows, its reason as `%@`. (A load under way shows ``Label/loading``.)
    /// Internal to the package, as the file panel's words are.
    package enum ImagePlaceholder: String, CaseIterable {
        case failed = "imagePlaceholder.failed"
    }
}

extension LocalizationKey.ImagePlaceholder: FrameworkLocalizationKey {}
