// SwiftUI's spelling of a paragraph's alignment, guarded as SwiftUI's must be
// at a macOS 15 deployment target: set, read, merged and the types named.
import Foundation

#if WITH_APPKIT
    import AppKit
#endif
#if WITH_SWIFTUI
    import SwiftUI
#else
    import StandIn
#endif

@available(macOS 15, *)
func guardedAlignment() {
    if #available(macOS 26, *) {
        var string = AttributedString("Chapter One\nIt was a dark and stormy night.")
        string.alignment = .center
        let named: AttributedString.TextAlignment = .right
        string.alignment = named
        var container = AttributeContainer()
        container.alignment = .left
        string.mergeAttributes(container)
        let read: AttributedString.TextAlignment? = string.runs.first?.alignment
        _ = read
        _ = AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self
    }
}
