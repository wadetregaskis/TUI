// Compile-only questions about SwiftUI's Table surface (swiftc -typecheck).
import SwiftUI

struct P: Identifiable { var id: Int; var name: String; var age: Int; var kids: [P]? }

// 1. A standalone String key-path column: which init wins?
@MainActor func standalone() {
    let c = TableColumn("Name", value: \P.name)
    print(type(of: c))
}

// 2. Mixed sortable and unsortable columns in a sorted table.
struct Mixed: View {
    @State var people: [P] = []
    @State var order = [KeyPathComparator(\P.name)]
    var body: some View {
        Table(people, sortOrder: $order) {
            TableColumn("Name", value: \.name)
            TableColumn("Age") { Text("\($0.age)") }
            TableColumn("Age2", value: \.age) { Text("\($0.age)") }
        }
    }
}

// 3. if / ForEach / Section in the builders.
struct Builders: View {
    @State var people: [P] = []
    var flag = true
    var body: some View {
        Table(of: P.self) {
            TableColumn("Name", value: \.name)
            if flag { TableColumn("Age") { Text("\($0.age)") } }
        } rows: {
            TableRow(P(id: 0, name: "a", age: 1))
            ForEach(people) { TableRow($0) }
            Section("Header") { ForEach(people) { TableRow($0) } }
            if flag { TableRow(P(id: 9, name: "z", age: 9)) }
        }
    }
}

// 4. Hierarchical.
struct Tree: View {
    @State var people: [P] = []
    var body: some View {
        Table(people, children: \.kids) {
            TableColumn("Name", value: \.name)
        }
        Table(of: P.self) {
            TableColumn("Name", value: \.name)
        } rows: {
            OutlineGroup(people, children: \.kids) { TableRow($0) }
        }
    }
}

// 5. A Sort-generic column built with sortUsing.
struct Desc: View {
    @State var people: [P] = []
    @State var order = [SortDescriptor(\P.name)]
    var body: some View {
        Table(people, sortOrder: $order) {
            TableColumn("Name", sortUsing: SortDescriptor(\P.name)) { Text($0.name) }
        }
    }
}

// 6. Is a String key-path column in a SortDescriptor table accepted?
// (It needs Sort == KeyPathComparator, so it should NOT compile; checked separately.)
