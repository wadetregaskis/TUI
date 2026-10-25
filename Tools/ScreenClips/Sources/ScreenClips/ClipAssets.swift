//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClipAssets.swift
//
//  Where a clip's pictures are: beside the player, where regenerate.sh stages
//  them: the photos make_photos.py paints.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

enum ClipAssets {
    /// The directory the player runs from.
    static let directory = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        .deletingLastPathComponent()

    /// A staged file, by its path relative to the player.
    static func path(_ name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    /// One of make_photos.py's pictures, by name (`glacier`).
    static func photo(_ name: String) -> String {
        path("photos/\(name).png")
    }
}
