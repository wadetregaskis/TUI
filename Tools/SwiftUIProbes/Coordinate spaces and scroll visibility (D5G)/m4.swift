import SwiftUI
import AppKit

@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<AnyView> {
    let h = NSHostingView(rootView: AnyView(v))
    h.frame = NSRect(origin: .zero, size: size)
    h.layoutSubtreeIfNeeded()
    return h
}

struct Probe: View {
    let tag: String
    var body: some View {
        GeometryReader { g in
            let _ = print(tag, "frame(in: .scrollView)=", g.frame(in: .scrollView),
                          " bounds(of: .scrollView)=", String(describing: g.bounds(of: .scrollView)),
                          " bounds(of: .scrollView(axis: .horizontal))=", String(describing: g.bounds(of: .scrollView(axis: .horizontal))),
                          " frame(in: .scrollView(axis: .vertical))=", g.frame(in: .scrollView(axis: .vertical)),
                          " frame(in: .scrollView(axis: .horizontal))=", g.frame(in: .scrollView(axis: .horizontal)),
                          " named(missing)=", g.frame(in: .named("missing")),
                          " bounds(of: named(missing))=", String(describing: g.bounds(of: .named("missing"))),
                          " global=", g.frame(in: .global))
            Color.clear
        }
        .frame(width: 30, height: 20)
    }
}

struct NoScroll: View {
    var body: some View {
        Probe(tag: "noscroll").padding(.leading, 7).padding(.top, 9).frame(width: 100, height: 100, alignment: .topLeading)
    }
}

// A horizontal scroll view inside a vertical one: which does .scrollView pick?
struct Nested: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.red.frame(height: 5)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        Color.green.frame(width: 3)
                        Probe(tag: "nested")
                    }
                }.frame(width: 80, height: 20).padding(.leading, 4)
                Color.blue.frame(height: 200)
            }
        }
        .frame(width: 100, height: 100).padding(.leading, 7).padding(.top, 9)
    }
}

@MainActor func run() {
    _ = host(NoScroll(), size: CGSize(width: 100, height: 100))
    _ = host(Nested(), size: CGSize(width: 107, height: 109))
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
