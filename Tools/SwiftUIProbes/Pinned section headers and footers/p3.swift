import SwiftUI
import AppKit

// P3: grid columns (debug), List header geometry, scrollTo under a pinned header.

let hc: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0), .init(red: 0, green: 0, blue: 1)]
let rc: [Color] = [.init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1), .init(red: 1, green: 0, blue: 1)]
let fc: [Color] = [.init(red: 1, green: 0.5, blue: 0), .init(red: 0.5, green: 0, blue: 1), .init(red: 0, green: 0.5, blue: 0.5)]

@MainActor var frames: [String: CGRect] = [:]

struct Track: ViewModifier {
    let tag: String
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in
            MainActor.assumeIsolated { frames[tag] = r }
        }
    }
}

struct ListSections: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { s in
            Section {
                ForEach((s * 100)..<(s * 100 + 8), id: \.self) { i in Text("row \(i)").frame(height: 40).modifier(Track(tag: "row\(i)")) }
            } header: {
                Text("Header \(s)").modifier(Track(tag: "H\(s)"))
            } footer: {
                Text("Footer \(s)").modifier(Track(tag: "F\(s)"))
            }
        }
    }
}

@MainActor func listRun(_ name: String, _ v: some View) {
    print("== \(name)")
    frames = [:]
    let h = host(v.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.5)
    print("  window frame", h.window?.frame as Any)
    for y in [0.0, 60, 200, 400] {
        scroll(h, to: NSPoint(x: 0, y: y)); spin(0.2)
        let keys = ["H0", "H1", "H2", "F0", "F1", "row0", "row7", "row100"]
        print("  off \(Int(y)) clip \(Int(clipOrigin(h).y)): " + keys.compactMap { k in frames[k].map { "\(k)=y\(Int($0.minY + 5000 - 0))h\(Int($0.height))" } }.joined(separator: " "))
    }
}

struct SeekProbe: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(0..<3, id: \.self) { s in
                        Section {
                            ForEach((s * 100)..<(s * 100 + 8), id: \.self) { i in rc[s].frame(height: 40).id(i) }
                        } header: { hc[s].frame(height: 30) } footer: { fc[s].frame(height: 20) }
                    }
                }
            }
            .onAppear { seek = { id in proxy.scrollTo(id, anchor: .top) } }
        }
    }
}
@MainActor var seek: ((Int) -> Void)?

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            print("== grid debug")
            let grid = ScrollView { LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(0..<3, id: \.self) { s in
                    Section {
                        ForEach((s * 100)..<(s * 100 + 7), id: \.self) { _ in rc[s].frame(height: 40) }
                    } header: { hc[s].frame(height: 30) } footer: { fc[s].frame(height: 20) }
                }
            } }
            let h = host(grid.environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
            for y in [0.0, 100, 140] {
                scroll(h, to: NSPoint(x: 0, y: y))
                if let rep = capture(h) {
                    print("  rep \(rep.pixelsWide)x\(rep.pixelsHigh)")
                    for x in [5.0, 100, 150, 200, 280] { print("  off \(Int(y)) x\(Int(x)): \(columnRuns(rep, x: x, pointsHigh: 300))") }
                }
            }

            listRun("list plain", List { ListSections() }.listStyle(.plain))
            listRun("list sidebar", List { ListSections() }.listStyle(.sidebar))
            listRun("list inset", List { ListSections() }.listStyle(.inset))
            listRun("list automatic", List { ListSections() })
            listRun("lazyvstack pinned (control)", ScrollView { LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) { ListSections() } })

            print("== seek under pinned header")
            let s = host(SeekProbe().environment(\.colorScheme, .light), size: CGSize(width: 300, height: 300)); spin(0.4)
            for target in [3, 103, 105, 7] {
                seek?(target); spin(0.4)
                if let rep = capture(s) { print("  scrollTo(\(target), .top) clip \(Int(clipOrigin(s).y)): \(columnRuns(rep, x: 5, pointsHigh: 300))") }
            }
        }
    }
}
