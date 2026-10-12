import SwiftUI
import AppKit

// P5: where a grid puts a narrow header and footer, and the spacing around them.

let hc: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0), .init(red: 0, green: 0, blue: 1)]
let rc: [Color] = [.init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 1)]
let fc: [Color] = [.init(red: 1, green: 0.5, blue: 0), .init(red: 0.5, green: 0, blue: 1), .init(red: 0, green: 0.5, blue: 0.5)]

@MainActor func grid(_ alignment: HorizontalAlignment, spacing: CGFloat) -> some View {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
                  alignment: alignment, spacing: spacing, pinnedViews: [.sectionHeaders]) {
            ForEach(0..<2, id: \.self) { s in
                Section {
                    ForEach((s * 100)..<(s * 100 + 4), id: \.self) { _ in rc[s].frame(width: 20, height: 40) }
                } header: { hc[s].frame(width: 50, height: 30) } footer: { fc[s].frame(width: 50, height: 20) }
            }
        }
    }.frame(width: 300, height: 300)
}

@MainActor func vstack(_ alignment: HorizontalAlignment) -> some View {
    ScrollView {
        LazyVStack(alignment: alignment, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(0..<2, id: \.self) { s in
                Section {
                    ForEach((s * 100)..<(s * 100 + 4), id: \.self) { _ in rc[s].frame(width: 20, height: 40) }
                } header: { hc[s].frame(width: 50, height: 30) } footer: { fc[s].frame(width: 50, height: 20) }
            }
        }
    }.frame(width: 300, height: 300)
}

@MainActor func show(_ name: String, _ v: some View) {
    print("== \(name)")
    let h = host(v.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
    if let rep = capture(h) {
        for y in [5.0, 35, 75, 160, 185] { print("  y\(Int(y)): \(rowRuns(rep, y: y, pointsWide: 300))") }
        print("  x5: \(columnRuns(rep, x: 5, pointsHigh: 300))")
        print("  x150: \(columnRuns(rep, x: 150, pointsHigh: 300))")
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            show("grid center spacing 0", grid(.center, spacing: 0))
            show("grid leading spacing 0", grid(.leading, spacing: 0))
            show("grid center spacing 10", grid(.center, spacing: 10))
            show("vstack center", vstack(.center))
            show("vstack leading", vstack(.leading))
        }
    }
}
