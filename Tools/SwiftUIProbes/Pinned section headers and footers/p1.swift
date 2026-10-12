import SwiftUI
import AppKit

// P1: vertical LazyVStack pinning. Three sections of header 30, eight rows of
// 40, footer 20 = 370 each; 1110 tall in a 300-tall viewport.

let hc: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0), .init(red: 0, green: 0, blue: 1)]
let rc: [Color] = [.init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 1)]
let fc: [Color] = [.init(red: 1, green: 0.5, blue: 0), .init(red: 0.5, green: 0, blue: 1), .init(red: 0, green: 0.5, blue: 0.5)]

struct Sections: View {
    var headerH: [Double] = [30, 30, 30]
    var rows: [Int] = [8, 8, 8]
    var footer = true
    var header = true
    var headerWidth: Double? = nil
    var body: some View {
        ForEach(0..<3, id: \.self) { s in
            Section {
                ForEach((s * 100)..<(s * 100 + rows[s]), id: \.self) { _ in rc[s].frame(height: 40) }
            } header: {
                if header {
                    if let w = headerWidth {
                        hc[s].frame(width: w, height: headerH[s]).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        hc[s].frame(height: headerH[s])
                    }
                }
            } footer: {
                if footer { fc[s].frame(height: 20) }
            }
        }
    }
}

@MainActor func run(_ name: String, _ v: some View, offsets: [Double], xs: [Double] = [5]) {
    print("== \(name)")
    let h = host(v.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
    for y in offsets {
        scroll(h, to: NSPoint(x: 0, y: y))
        guard let rep = capture(h) else { continue }
        for x in xs {
            print("  off \(Int(y)) (clip \(Int(clipOrigin(h).y))) x\(Int(x)): \(columnRuns(rep, x: x, pointsHigh: 300))")
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let offs: [Double] = [0, 50, 75, 80, 90, 100, 200, 320, 330, 340, 350, 360, 370, 380, 450, 700, 810]
            run("none pinned", ScrollView { LazyVStack(spacing: 0) { Sections() } }, offsets: [0, 100, 330, 350])
            run("headers", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections() } }, offsets: offs)
            run("footers", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionFooters) { Sections() } }, offsets: offs)
            run("both", ScrollView { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) { Sections() } }, offsets: offs)
            run("headers, no footers", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections(footer: false) } }, offsets: [300, 310, 320, 330, 340, 350])
            run("tall header 100 over one row", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections(headerH: [100, 30, 30], rows: [1, 8, 8], footer: false) } }, offsets: [0, 20, 40, 60, 100, 139, 140, 150])
            run("narrow header (transparency)", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections(headerWidth: 50) } }, offsets: [0, 100], xs: [5, 150])
            run("spacing 10", ScrollView { LazyVStack(spacing: 10, pinnedViews: .sectionHeaders) { Sections() } }, offsets: [0, 100, 300, 350, 380, 400, 420])
            run("stack below 100pt of other content", ScrollView { VStack(spacing: 0) { Color.gray.frame(height: 100); LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections() } } }, offsets: [0, 50, 100, 150, 450])
            run("no ScrollView (frame 300)", LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { Sections() }.frame(height: 300, alignment: .top).clipped(), offsets: [0])
        }
    }
}
