import SwiftUI
import AppKit

// P2: footer clamp, grids, horizontal stacks, Lists, scrollTo under a pinned
// header, a section nested inside a row, a Section wrapped in a modifier.

let hc: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0), .init(red: 0, green: 0, blue: 1)]
let rc: [Color] = [.init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 1)]
let fc: [Color] = [.init(red: 1, green: 0.5, blue: 0), .init(red: 0.5, green: 0, blue: 1), .init(red: 0, green: 0.5, blue: 0.5)]

struct VSections: View {
    var rows = 8
    var body: some View {
        ForEach(0..<3, id: \.self) { s in
            Section {
                ForEach((s * 100)..<(s * 100 + rows), id: \.self) { _ in rc[s].frame(height: 40) }
            } header: {
                hc[s].frame(height: 30)
            } footer: {
                fc[s].frame(height: 20)
            }
        }
    }
}

struct HSections: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { s in
            Section {
                ForEach((s * 100)..<(s * 100 + 8), id: \.self) { _ in rc[s].frame(width: 40) }
            } header: {
                hc[s].frame(width: 30)
            } footer: {
                fc[s].frame(width: 20)
            }
        }
    }
}

struct GridSections: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { s in
            Section {
                ForEach((s * 100)..<(s * 100 + 7), id: \.self) { _ in rc[s].frame(height: 40) }
            } header: {
                hc[s].frame(height: 30)
            } footer: {
                fc[s].frame(height: 20)
            }
        }
    }
}

@MainActor func runV(_ name: String, _ v: some View, offsets: [Double], xs: [Double] = [5], size: CGSize = CGSize(width: 300, height: 300)) {
    print("== \(name)")
    let h = host(v.environment(\.colorScheme, .light), size: size); spin(0.4)
    for y in offsets {
        scroll(h, to: NSPoint(x: 0, y: y))
        guard let rep = capture(h) else { continue }
        for x in xs {
            print("  off \(Int(y)) (clip \(Int(clipOrigin(h).y))) x\(Int(x)): \(columnRuns(rep, x: x, pointsHigh: size.height))")
        }
    }
}

@MainActor func runH(_ name: String, _ v: some View, offsets: [Double], ys: [Double] = [5]) {
    print("== \(name)")
    let h = host(v.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 100)); spin(0.4)
    for x in offsets {
        scroll(h, to: NSPoint(x: x, y: 0))
        guard let rep = capture(h) else { continue }
        for y in ys {
            print("  off \(Int(x)) (clip \(Int(clipOrigin(h).x))) y\(Int(y)): \(rowRuns(rep, y: y, pointsWide: 300))")
        }
    }
}

@Observable final class Ctl { var pos = ScrollPosition(idType: Int.self) }

struct SeekProbe: View {
    @Bindable var ctl: Ctl
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { VSections() }
                .scrollTargetLayout()
        }
        .scrollPosition($ctl.pos)
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            runV("footers: clamp at content top", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionFooters) { VSections() } },
                 offsets: [100, 101, 105, 110, 115, 120, 125, 130, 140])
            runV("both, short section (2 rows)", ScrollView { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) { VSections(rows: 2) } },
                 offsets: [0, 20, 40, 60, 80, 100, 120, 150])
            runV("grid 3 cols headers", ScrollView { LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) { GridSections() } },
                 offsets: [0, 50, 100, 140, 150, 200], xs: [5, 150, 295])
            runH("hstack headers+footers", ScrollView(.horizontal) { LazyHStack(spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) { HSections() } },
                 offsets: [0, 50, 100, 320, 340, 350, 360, 400])
            runH("hgrid 2 rows headers", ScrollView(.horizontal) { LazyHGrid(rows: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0, pinnedViews: [.sectionHeaders]) { HSections() } },
                 offsets: [0, 50, 100, 150], ys: [5, 95])
            runV("plain VStack in ScrollView (sections, no pinning API)", ScrollView { VStack(spacing: 0) { VSections() } }, offsets: [100])
            runV("section nested in a row of a pinned stack", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { VStack(spacing: 0) { VSections() } } }, offsets: [100])
            runV("sections padded (modifier on Section)", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(0..<3, id: \.self) { s in
                    Section { ForEach((s * 100)..<(s * 100 + 8), id: \.self) { _ in rc[s].frame(height: 40) } } header: { hc[s].frame(height: 30) }
                        .padding(.top, 10)
                }
            } }, offsets: [0, 100])
            runV("list plain", List { VSections() }.listStyle(.plain), offsets: [0, 100, 330, 360])
            runV("list sidebar", List { VSections() }.listStyle(.sidebar), offsets: [0, 100, 330, 360])
            runV("list inset", List { VSections() }.listStyle(.inset), offsets: [0, 100, 330, 360])
            runV("list automatic", List { VSections() }, offsets: [0, 100, 330, 360])

            // scrollTo(id, anchor: .top) with a pinned header above
            let ctl = Ctl()
            print("== seek under pinned header")
            let h = host(SeekProbe(ctl: ctl).environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
            for target in [3, 103, 105] {
                ctl.pos.scrollTo(id: target, anchor: .top); spin(0.4)
                if let rep = capture(h) { print("  scrollTo(\(target), .top) clip \(Int(clipOrigin(h).y)): \(columnRuns(rep, x: 5, pointsHigh: 300))") }
            }
        }
    }
}
