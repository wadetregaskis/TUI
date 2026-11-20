// SwiftUI's spelling with no availability guard. At a macOS 15 deployment
// target SwiftUI refuses it ("only available in macOS 26 or newer"), and so
// does TUI wherever Core Text's type is the one in use; at a macOS 26 target,
// and wherever TUI's own type is in use, it compiles.
import Foundation

#if WITH_APPKIT
    import AppKit
#endif
#if WITH_SWIFTUI
    import SwiftUI
#else
    import StandIn
#endif

func unguardedAlignment() {
    var string = AttributedString("Chapter One")
    string.alignment = .center
    _ = string
}
