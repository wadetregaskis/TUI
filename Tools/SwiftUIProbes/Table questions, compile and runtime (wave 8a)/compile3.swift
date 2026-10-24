// The corpus's row shapes, against SwiftUI.
import SwiftUI

struct TableRowShapes: View {
    struct Purchase: Identifiable {
        let id: Int
        var item: String
        var price: Double
    }

    struct Specials: TableRowContent {
        let purchases: [Purchase]

        @TableRowBuilder<Purchase>
        var tableRowBody: some TableRowContent<Purchase> {
            ForEach(purchases) { purchase in
                TableRow(purchase)
            }
        }
    }

    @State private var purchases: [Purchase] = []
    @State private var selection: Purchase.ID?
    @State private var sortOrder = [KeyPathComparator(\Purchase.item)]
    let showsTotal: Bool

    var body: some View {
        VStack {
            Table(of: Purchase.self) {
                TableColumn("Item", value: \.item)
                TableColumn("Price") { Text($0.price, format: .number) }
            } rows: {
                TableRow(Purchase(id: 0, item: "Coffee", price: 2.5))
                ForEach(purchases) { TableRow($0) }
                ForEach(purchases)
                if showsTotal {
                    TableRow(Purchase(id: -1, item: "Total", price: 0))
                }
                Group {
                    Specials(purchases: purchases)
                }
            }
            Table(selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Item", value: \.item)
            } rows: {
                ForEach(purchases) { TableRow($0) }
            }
        }
    }
}
