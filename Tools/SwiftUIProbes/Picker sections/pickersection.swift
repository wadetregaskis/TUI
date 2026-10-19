// How a macOS SwiftUI Picker draws a Section's header: reads back the menu of
// the NSPopUpButton a .menu picker makes, and prints each item's title and kind
// — and, for a section a condition empties, the collapsed control's width.
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift pickersection.swift -o ps && ./ps
import SwiftUI
import AppKit

@MainActor func popups(_ v: NSView) -> [NSPopUpButton] {
    var out: [NSPopUpButton] = []
    if let p = v as? NSPopUpButton { out.append(p) }
    for c in v.subviews { out += popups(c) }
    return out
}

@MainActor func dump<V: View>(_ name: String, _ view: V) {
    let h = host(view, size: CGSize(width: 300, height: 200))
    spin(0.5)
    for p in popups(h) {
        print("\(name): \(p.numberOfItems) items, selected=\(p.indexOfSelectedItem) width=\(p.frame.width)")
        for item in p.itemArray {
            var kind = "option"
            if item.isSeparatorItem { kind = "separator" }
            if #available(macOS 14.0, *), item.isSectionHeader { kind = "sectionHeader" }
            print("  [\(kind)] '\(item.title)' enabled=\(item.isEnabled) indent=\(item.indentationLevel)")
        }
    }
}

struct Sectioned: View {
    @State var choice = 2
    var body: some View {
        Picker("P", selection: $choice) {
            Section("Fruit") {
                Text("Apple").tag(1)
                Text("Pear").tag(2)
            }
            Section("Veg") {
                Text("Kale").tag(3)
            }
            Text("Loose").tag(4)
        }
        .pickerStyle(.menu)
    }
}

struct HeaderOnlyFirst: View {
    @State var choice = 1
    var body: some View {
        Picker("P", selection: $choice) {
            Text("First").tag(1)
            Section {
                Text("Second").tag(2)
            } header: {
                Text("Group")
            }
            Section {
                Text("Third").tag(3)
            }
        }
        .pickerStyle(.menu)
    }
}

/// One option, at the width it needs: the control the emptied section is
/// measured against.
struct Baseline: View {
    @State var choice = 2
    var body: some View {
        Picker("P", selection: $choice) {
            Text("Apple").tag(2)
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// A section whose only option a condition removes.
struct Emptied: View {
    @State var choice = 2
    let showCitrus: Bool
    var body: some View {
        Picker("P", selection: $choice) {
            Section("Citrus fruit of a long name") {
                if showCitrus { Text("Lemon").tag(1) }
            }
            Text("Apple").tag(2)
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            dump("sectioned", Sectioned())
            dump("headerOnlyFirst", HeaderOnlyFirst())
            dump("baseline", Baseline())
            dump("emptied", Emptied(showCitrus: false))
            dump("filled", Emptied(showCitrus: true))
        }
    }
}
