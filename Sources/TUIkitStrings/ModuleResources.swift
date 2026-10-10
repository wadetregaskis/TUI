//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModuleResources.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Finding this module's own resources

/// This module's resource bundle — `TUIkit_TUIkitStrings`, which holds the
/// translation tables and `VERSION` — and the files in it.
///
/// A value rather than a function of `Bundle.module`, so that what reads the
/// files (``LocalizationService``, `tuiKitVersion`) can be handed a bundle of a
/// test's own, or none.
package struct ModuleResources: Sendable {
    /// The bundle's directory, or `nil` for none.
    package let bundleURL: URL?

    /// No bundle at all.
    package static let absent = Self(bundleURL: nil)

    /// This program's bundle.
    package static let current = Self(bundleURL: Bundle.module.bundleURL)

    /// The resources in the bundle at `bundleURL`, or none for `nil`.
    package init(bundleURL: URL?) {
        self.bundleURL = bundleURL
    }

    /// The URL of a file in the bundle — asked of the bundle first, and worked
    /// out from the bundle's location second; `nil` only where there is no
    /// bundle.
    ///
    /// The second half is not belt and braces. `url(forResource:withExtension:
    /// subdirectory:)` is implemented only where Foundation's bundle machinery
    /// is: on WebAssembly it returns `nil` for a file sitting in the directory
    /// the bundle names. Since the layout of a SwiftPM resource bundle is not a
    /// mystery — the files are where the build put them, under the bundle URL —
    /// the fallback simply looks.
    ///
    /// The consequence of not having it is quiet rather than loud, which is why
    /// it is worth a named function: the framework's own strings come back as
    /// their keys (`statusbar.quit` across the bottom of the screen) and its
    /// version reads `unknown`. That is exactly how the first WebAssembly build
    /// came up.
    ///
    /// - Parameters:
    ///   - name: The resource's file name, without extension.
    ///   - fileExtension: The extension, or `nil` for a file that has none.
    ///   - subdirectory: A directory within the bundle, or `nil` for its root.
    /// - Returns: A URL that may or may not exist — the caller reads it and
    ///   handles failure, as it would have to with any bundle lookup — or `nil`
    ///   where there is no bundle.
    package func url(named name: String, extension fileExtension: String?, subdirectory: String? = nil) -> URL? {
        guard let bundleURL else { return nil }
        if let found = Bundle(url: bundleURL)?.url(
            forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
        {
            return found
        }
        var url = bundleURL
        if let subdirectory { url.appendPathComponent(subdirectory) }
        let fileName = fileExtension.map { "\(name).\($0)" } ?? name
        return url.appendingPathComponent(fileName)
    }
}
