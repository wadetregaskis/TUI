//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipAssets.swift
//
//  Where a clip's pictures are: beside the player, where regenerate.sh stages
//  them: the owner's photographs, from Photos/.
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

    /// One of the photographs in Photos/, by name (`burrowing-owl`).
    static func photo(_ name: String) -> String {
        path("photos/\(name).webp")
    }
}
