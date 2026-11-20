// TUI's own attribute, under a name SwiftUI does not use: no guard at any
// deployment target, on every platform and SDK.
import Foundation
import StandIn

#if WITH_APPKIT
    import AppKit
#endif

func fallbackAlignment() {
    var string = AttributedString("Chapter One\nIt was a dark and stormy night.")
    string.paragraphAlignment = .center
    var container = AttributeContainer()
    container.paragraphAlignment = .trailing
    string.mergeAttributes(container)
    let named: TextAlignment? = string.runs.first?.paragraphAlignment
    _ = named
    _ = string.runs.first.map(drawnAlignment(of:))
}
