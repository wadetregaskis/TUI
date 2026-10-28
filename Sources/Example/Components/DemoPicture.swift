//  🖥️ TUI — A Terminal UI framework for Swift
//  DemoPicture.swift
//
//  The pictures the image page carries, to flick between without finding one
//  of your own: the mascot of each platform TUI runs on, the one it is
//  running on shown first, and a photograph.
//
//  Credits: Tux by Larry Ewing (lewing@isc.tamu.edu), drawn with The GIMP.
//  Lil' Finder Guy and the Swift logo are Apple's, Touko Madobe is
//  Microsoft's (Windows 7's Japanese mascot).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// A picture bundled with the Example, in `Resources/`.
enum DemoPicture: CaseIterable {
    case macOS
    case linux
    case windows
    case wasm
    case photo

    /// The mascot of the platform the Example is running on: Lil' Finder
    /// Guy on macOS, Tux on Linux, Touko Madobe on Windows, and the Swift
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

    /// The status bar's label: the picture's name, as `chars:` names the
    /// charset. Names, so not translated.
    var label: String {
        switch self {
        case .macOS: "picture:finder"
        case .linux: "picture:tux"
        case .windows: "picture:touko"
        case .wasm: "picture:swift"
        case .photo: "picture:photo"
        }
    }

    /// The picture `steps` along the list, wrapping at either end.
    func cycled(by steps: Int) -> Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[((index + steps) % all.count + all.count) % all.count]
    }
}
