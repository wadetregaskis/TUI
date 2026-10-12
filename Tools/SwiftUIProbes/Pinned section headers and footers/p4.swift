import SwiftUI
import AppKit

// P4: grids with a fixed frame (P2/P3's grids shrank the host to their ideal width).

let hc: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0), .init(red: 0, green: 0, blue: 1)]
let rc: [Color] = [.init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 1)]
let fc: [Color] = [.init(red: 1, green: 0.5, blue: 0), .init(red: 0.5, green: 0, blue: 1), .init(red: 0, green: 0.5, blue: 0.5)]

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            print("== grid 3 cols, 7 items/section, headers+footers pinned, frame 300")
            let grid = ScrollView { LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                ForEach(0..<3, id: \.self) { s in
                    Section {
                        ForEach((s * 100)..<(s * 100 + 7), id: \.self) { _ in rc[s].frame(height: 40) }
                    } header: { hc[s].frame(height: 30) } footer: { fc[s].frame(height: 20) }
                }
            } }.frame(width: 300, height: 300)
            let h = host(grid.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
            for y in [0.0, 100, 140, 160] {
                scroll(h, to: NSPoint(x: 0, y: y))
                if let rep = capture(h) {
                    for x in [5.0, 150, 280] { print("  off \(Int(y)) x\(Int(x)): \(columnRuns(rep, x: x, pointsHigh: 300))") }
                }
            }
            print("== hgrid 2 rows, frame 300x100")
            let hg = ScrollView(.horizontal) { LazyHGrid(rows: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(0..<3, id: \.self) { s in
                    Section {
                        ForEach((s * 100)..<(s * 100 + 7), id: \.self) { _ in rc[s].frame(width: 40) }
                    } header: { hc[s].frame(width: 30) } footer: { fc[s].frame(width: 20) }
                }
            } }.frame(width: 300, height: 100)
            let g = host(hg.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 100)); spin(0.4)
            for x in [0.0, 100, 150] {
                scroll(g, to: NSPoint(x: x, y: 0))
                if let rep = capture(g) {
                    for y in [5.0, 95] { print("  off \(Int(x)) y\(Int(y)): \(rowRuns(rep, y: y, pointsWide: 300))") }
                }
            }
        }
    }
}
