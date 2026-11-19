//  🖥️ TUI — A Terminal UI framework for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -O -parse-as-library -c -o /dev/null Crash.swift
//
// That is enough for a swift.org toolchain on macOS. Xcode's swiftc, called by
// its path, also needs `-sdk`, from an xcrun that DEVELOPER_DIR points at Xcode
// (a prefix assignment would not reach the xcrun inside `$(...)`):
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -O -parse-as-library \
//       -sdk "$(xcrun --sdk macosx --show-sdk-path)" -c -o /dev/null Crash.swift
//
// Aborts every 6.2.4 at -O, with or without assertions, in the SIL verifier
// that runs before a function's ownership is lowered:
//
//   SIL verification failed: Load borrow invalidated by a local write
//
// -Onone compiles it.

/// A class whose method may release something: it stores a `String`.
final class Box {
    var name = ""

    func reset(_ unshared: Bool) {
        if unshared { name = "" }
    }
}

/// The uniqueness check as the argument of a call on the variable it checks,
/// with a `guard` between the variable's initialization and the call.
func edit(_ box: Box, _ flag: Bool) {
    var before = box
    guard flag else { return }
    before.reset(isKnownUniquelyReferenced(&before))
}
