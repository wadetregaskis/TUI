//  🖥️ TUI — A Terminal UI framework for Swift
//  ModuleResources.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Finding this module's own resources

/// This module's resource bundle — `TUI_TUIStrings`, which holds the
/// translation tables and `VERSION` — and the files in it; or none, without
/// stopping the program.
///
/// A value rather than a function of `Bundle.module`, so that what reads the
/// files (``LocalizationService``, `tuiVersion`) can be handed a bundle of a
/// test's own, or none — and because `Bundle.module` stops the program
/// (`fatalError`) where it finds no bundle. A terminal program is often shipped
/// as one file, copied out of `.build` or installed by a formula, so that was
/// every such program, at launch. Where this finds none, TUI's words read in
/// English (`LocalizationService.builtInEnglish`) and `tuiVersion` reads
/// `unknown`.
///
/// ## Where it looks
///
/// For a directory named `TUI_TUIStrings.bundle` (SwiftPM's name on
/// Apple platforms) or `TUI_TUIStrings.resources` (elsewhere), in the
/// directories Foundation reports for the program and for this code, in order:
///
/// 1. the main bundle's directory — a command-line tool's own, where
///    `swift build` puts the bundle beside the executable, and where an
///    installer copies the two;
/// 2. the main bundle's resources — an app's `Contents/Resources`;
/// 3. the resources of the bundle this code is in — a framework's; the test
///    bundle Swift Build copies the bundle into; and a command-line tool's real
///    directory where it was started through a symbolic link;
/// 4. the directory holding that bundle, when it is not the main bundle —
///    where SwiftPM's native build system leaves the resource bundle beside the
///    `.xctest` that `swift test` loads into a runner from the toolchain.
///
/// ## What it is not
///
/// Not a copy of SwiftPM's accessor, and not a check made before calling it.
/// There are two accessors, and they look in different places (read in each
/// generated `resource_bundle_accessor.swift`, 2026-10-10; decisions BNDL):
/// the native build system's looks beside the main bundle and then at the
/// build directory, by an absolute path compiled in; Swift Build's — SwiftPM
/// 6.4's default — at 2, 3 and 1 above, and never at the build directory.
/// Neither can be asked whether it would find the bundle, and nothing checked
/// here would prove that the one compiled in will, so neither is called.
/// Places 1 to 3 are Swift Build's own; 4 stands in for the native build's
/// compiled-in path in the one layout that needs it.
///
/// That path itself is not read: it can be read only through the accessor, and
/// it names a directory on the machine that built the program. So a program
/// copied out of its build directory reads the bundle beside it or none — on
/// the machine that built it as on any other (decisions BNDL).
///
/// On WebAssembly it is still `Bundle.module`. There SwiftPM compiles both of
/// its places in as absolute paths, and the page serves the bundle at the
/// build directory's (`Tools/Web/build.sh`): there is nothing to look for at
/// run time, and a page that serves no bundle still stops the program.
package struct ModuleResources: Sendable {
    /// The bundle's directory, or `nil` for none.
    package let bundleURL: URL?

    /// No bundle at all.
    package static let absent = Self(bundleURL: nil)

    /// This program's bundle, looked for once, the first time it is asked for.
    package static let current: Self = {
        #if canImport(WASILibc)
        Self(bundleURL: Bundle.module.bundleURL)
        #else
        Self(searching: searchDirectories())
        #endif
    }()

    /// The bundle's names: SwiftPM's — the package's name, an underscore, the
    /// target's — with the extension it gives a resource bundle on Apple
    /// platforms, and the one it gives it elsewhere.
    static let bundleNames = ["TUI_TUIStrings.bundle", "TUI_TUIStrings.resources"]

    /// The resources in the bundle at `bundleURL`, or none for `nil`.
    package init(bundleURL: URL?) {
        self.bundleURL = bundleURL
    }

    /// The resources in the first of `directories` that holds the bundle (a
    /// directory of one of ``bundleNames``), or none where none does. A `nil`
    /// directory is passed over.
    package init(searching directories: [URL?]) {
        self.init(bundleURL: Self.firstBundle(in: directories))
    }

    private static func firstBundle(in directories: [URL?]) -> URL? {
        let fileManager = FileManager.default
        for directory in directories {
            guard let directory else { continue }
            for name in bundleNames {
                let candidate = directory.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return nil
    }

    #if !canImport(WASILibc)
    /// The four places in "Where it looks", in order.
    static func searchDirectories() -> [URL?] {
        let main = Bundle.main
        let code = Bundle(for: ModuleResourcesAnchor.self)
        var directories: [URL?] = [main.bundleURL, main.resourceURL, code.resourceURL]
        if code.bundleURL.standardizedFileURL != main.bundleURL.standardizedFileURL {
            directories.append(code.bundleURL.deletingLastPathComponent())
        }
        return directories
    }
    #endif

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
    /// it is worth a named function: the framework's own strings come back in
    /// English whatever the language (or, before the English was compiled in,
    /// as their keys: `statusbar.quit` across the bottom of the screen) and its
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

#if !canImport(WASILibc)
/// A class in this module, for `Bundle(for:)`: the bundle this code was
/// loaded from.
private final class ModuleResourcesAnchor {}
#endif
