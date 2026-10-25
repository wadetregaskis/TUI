// swift-tools-version: 6.2

// The README's animated clips: TUIkit demos that play themselves in a real terminal, and the recorder that films
// the terminal's window. Run Tools/ScreenClips/regenerate.sh rather than this package directly; see README.md.
//
// Kept out of the root package, as Tools/Diagrams is, so the library's own graph and product list never see it.
// TUIkit is the checkout this package sits in, by path. A path dependency's identity is its directory's name, which
// is `tuikit` in a plain clone and the worktree's name in a worktree, so the manifest works it out rather than
// spelling it.
//
// macOS only: the recorder is ScreenCaptureKit, and the clips are of macOS terminals.

import Foundation
import PackageDescription

let root = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
let tuikit = root.lastPathComponent.lowercased()

let package = Package(
    name: "ScreenClips",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: root.path)],
    targets: [
        // The scenes, and the player that runs one under a pseudo-terminal of its own and types its script into it.
        .executableTarget(
            name: "ScreenClips",
            dependencies: [.product(name: "TUIkit", package: tuikit)]
        ),
        // Films one window to PNG frames with their presentation times, until the player says the scene is over.
        .executableTarget(name: "WindowRecorder"),
    ]
)
