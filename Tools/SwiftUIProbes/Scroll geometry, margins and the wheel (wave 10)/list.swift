import SwiftUI
import AppKit

struct RowY: View {
    let tag: String
    let i: Int
    var body: some View {
        Text("row \(i)").frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in
                if i == 0 { print(tag, "row0 global", r) }
            }
    }
}
struct Item: Identifiable { let id: Int }
@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 300, height: 300)
            _ = host(List(0..<30, id: \.self) { RowY(tag: "list plain", i: $0) }, size: sz); spin(0.5)
            _ = host(List(0..<30, id: \.self) { RowY(tag: "list margins top40", i: $0) }.contentMargins(.top, 40), size: sz); spin(0.5)
            _ = host(List(0..<30, id: \.self) { RowY(tag: "list margins h30", i: $0) }.contentMargins(.horizontal, 30), size: sz); spin(0.5)
            _ = host(List(0..<30, id: \.self) { RowY(tag: "list margins top40 scrollContent", i: $0) }.contentMargins(.top, 40, for: .scrollContent), size: sz); spin(0.5)
            _ = host(List(0..<30, id: \.self) { RowY(tag: "list safeArea top40", i: $0) }.safeAreaPadding(.top, 40), size: sz); spin(0.5)
            _ = host(Form { ForEach(0..<30, id: \.self) { RowY(tag: "form grouped plain", i: $0) } }.formStyle(.grouped), size: sz); spin(0.5)
            _ = host(Form { ForEach(0..<30, id: \.self) { RowY(tag: "form grouped top40", i: $0) } }.formStyle(.grouped).contentMargins(.top, 40), size: sz); spin(0.5)
            _ = host(Table((0..<30).map(Item.init)) { TableColumn("c") { RowY(tag: "table plain", i: $0.id) } }, size: sz); spin(0.5)
            _ = host(Table((0..<30).map(Item.init)) { TableColumn("c") { RowY(tag: "table top40", i: $0.id) } }.contentMargins(.top, 40), size: sz); spin(0.5)
            // Alignment role
            _ = host(ScrollView { VStack { ForEach(0..<3, id: \.self) { RowY(tag: "sv short plain", i: $0) } } }, size: sz); spin(0.5)
            _ = host(ScrollView { VStack { ForEach(0..<3, id: \.self) { RowY(tag: "sv short anchor.bottom (unlabelled)", i: $0) } } }.defaultScrollAnchor(.bottom), size: sz); spin(0.5)
            _ = host(ScrollView { VStack { ForEach(0..<3, id: \.self) { RowY(tag: "sv short anchor.bottom for alignment", i: $0) } } }.defaultScrollAnchor(.bottom, for: .alignment), size: sz); spin(0.5)
            _ = host(ScrollView { VStack { ForEach(0..<3, id: \.self) { RowY(tag: "sv short anchor.bottom for initialOffset", i: $0) } } }.defaultScrollAnchor(.bottom, for: .initialOffset), size: sz); spin(0.5)
            _ = host(List(0..<3, id: \.self) { RowY(tag: "list short plain", i: $0) }, size: sz); spin(0.5)
            _ = host(List(0..<3, id: \.self) { RowY(tag: "list short anchor.bottom (unlabelled)", i: $0) }.defaultScrollAnchor(.bottom), size: sz); spin(0.5)
            _ = host(List(0..<3, id: \.self) { RowY(tag: "list short anchor.bottom for alignment", i: $0) }.defaultScrollAnchor(.bottom, for: .alignment), size: sz); spin(0.5)
        }
    }
}
