//  🖥️ TUI — A Terminal UI framework for Swift
//  DemoPicture.swift
//
//  The pictures the image page carries, to flick between without finding one
//  of your own: the mascot of each platform TUI runs on, the one it is
//  running on shown first, and a photograph.
//
//  Credits: Tux by Larry Ewing (lewing@isc.tamu.edu), drawn with The GIMP.
//  Lil' Mac Guy and the Swift logo are Apple's, Touko Madobe is
//  Microsoft's (Windows 7's Japanese mascot). The photograph is an eagle.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// A picture bundled with the Example, in `Resources/`, in the order the
/// image page's combo box lists them and `p` steps through them.
enum DemoPicture: CaseIterable {
    case macOS
    case windows
    case linux
    case wasm
    case photo

    /// The mascot of the platform the Example is running on: Lil' Mac Guy
    /// on macOS, Tux on Linux, Touko Madobe on Windows, and the Swift
    /// bird in a browser, WebAssembly having no mascot of its own.
    ///
    /// The platform itself, not a capability, is the question here, so this
    /// asks `os(…)` rather than `canImport(…)`.
    static var platformDefault: Self {
        #if os(macOS)
            .macOS
        #elseif os(Windows)
            .windows
        #elseif os(WASI)
            .wasm
        #else
            .linux
        #endif
    }

    /// The picture the image page opens on: the one `TUI_EXAMPLE_PICTURE`
    /// names (by ``name``, any case: `TUI_EXAMPLE_PICTURE="Touko Madobe"`),
    /// for a clip or a screenshot of one in particular, else
    /// ``platformDefault``.
    static var first: Self {
        guard let wanted = ProcessInfo.processInfo.environment["TUI_EXAMPLE_PICTURE"]?.lowercased() else {
            return platformDefault
        }
        return allCases.first { $0.name.lowercased() == wanted } ?? platformDefault
    }

    /// The file's name in `Resources/`, and its extension.
    private var resource: (name: String, type: String) {
        switch self {
        case .macOS: ("mascot-macos", "jpg")
        case .linux: ("mascot-linux", "png")
        case .windows: ("mascot-windows", "jpg")
        case .wasm: ("mascot-wasm", "png")
        case .photo: ("demo-image", "jpg")
        }
    }

    /// Where the bundled file is, or `nil` if the bundle lacks it.
    var path: String? {
        Bundle.module.path(forResource: resource.name, ofType: resource.type, inDirectory: "Resources")
    }

    /// The file's name, for the message when it is missing.
    var fileName: String { "\(resource.name).\(resource.type)" }

    /// The picture's name, as the image page's combo box offers it rather
    /// than its file's path. A proper name, so not translated.
    var name: String {
        switch self {
        case .macOS: "Lil' Mac Guy"
        case .linux: "Tux"
        case .windows: "Touko Madobe"
        case .wasm: "Swift"
        case .photo: "Eagle"
        }
    }

    /// The bundled picture called `name`, ignoring case and the spaces around
    /// it, or `nil` if none is.
    static func named(_ name: String) -> Self? {
        let name = name.trimmingCharacters(in: .whitespaces)
        return allCases.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The status bar's label: the picture's name, as `chars:` names the
    /// charset. Names, so not translated.
    var label: String {
        switch self {
        case .macOS: "picture:mac"
        case .linux: "picture:tux"
        case .windows: "picture:touko"
        case .wasm: "picture:swift"
        case .photo: "picture:eagle"
        }
    }

    /// The picture `steps` along the list, wrapping at either end.
    func cycled(by steps: Int) -> Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[((index + steps) % all.count + all.count) % all.count]
    }
}
