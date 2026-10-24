import SwiftUI
import AppKit

@MainActor func snap<V: View>(_ v: V) -> (CGSize, Data) {
    let h = NSHostingView(rootView: v.fixedSize())
    let s = h.fittingSize
    h.frame = NSRect(origin: .zero, size: s)
    h.layoutSubtreeIfNeeded()
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return (s, Data()) }
    h.cacheDisplay(in: h.bounds, to: rep)
    return (s, rep.tiffRepresentation ?? Data())
}
@MainActor func cmp<A: View, B: View>(_ name: String, _ a: A, _ b: B) {
    let (sa, da) = snap(a); let (sb, db) = snap(b)
    print(name, "sizes", sa, sb, "pixels-identical:", da == db)
}
MainActor.assumeIsolated {
    cmp("submitLabel", TextField("Name", text: .constant("abc")).frame(width: 120), TextField("Name", text: .constant("abc")).frame(width: 120).submitLabel(.send))
    cmp("font.leading loose", Text("one\ntwo\nthree").font(.body), Text("one\ntwo\nthree").font(.body.leading(.loose)))
    cmp("font.leading tight", Text("one\ntwo\nthree").font(.body), Text("one\ntwo\nthree").font(.body.leading(.tight)))
    cmp("symbol hierarchical (single-layer 'star')", Image(systemName: "star"), Image(systemName: "star").symbolRenderingMode(.hierarchical))
    cmp("symbol hierarchical (multi-layer 'person.crop.circle.badge.plus')", Image(systemName: "person.crop.circle.badge.plus"), Image(systemName: "person.crop.circle.badge.plus").symbolRenderingMode(.hierarchical))
    cmp("symbol multicolor heart.fill", Image(systemName: "heart.fill"), Image(systemName: "heart.fill").symbolRenderingMode(.multicolor))
    cmp("controlSize large Button", Button("OK") {}, Button("OK") {}.controlSize(.large))
    cmp("controlSize mini Button", Button("OK") {}, Button("OK") {}.controlSize(.mini))
    cmp("textScale secondary", Text("Hello world"), Text("Hello world").textScale(.secondary))
    cmp("imageScale large", Image(systemName: "star"), Image(systemName: "star").imageScale(.large))
    cmp("scenePadding", Text("x"), Text("x").scenePadding())
    cmp("scenePadding minimum", Text("x"), Text("x").scenePadding(.minimum, edges: .all))
    cmp("fontDesign serif", Text("Hello"), Text("Hello").fontDesign(.serif))
    cmp("contentShape Rectangle (visual)", Text("Hello"), Text("Hello").contentShape(Rectangle()))
    cmp("sensoryFeedback success", Text("Hello"), Text("Hello").sensoryFeedback(.success, trigger: 1))
    cmp("allowsTightening", Text("Hello world, this is long").frame(width: 120), Text("Hello world, this is long").frame(width: 120).allowsTightening(true))
}
