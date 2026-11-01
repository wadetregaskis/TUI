
@main struct BenchApp: App {
    var body: some Scene { WindowGroup { BenchRoot() } }
}

@MainActor func startForever(_ change: () -> Void) {
    withAnimation(.linear(duration: 1).repeatForever(autoreverses: true)) { change() }
}

struct TRow: Identifiable, Sendable {
    let id: Int
    var a: String { "Row \(id)" }
    var b: String { "b\(id % 97)" }
    var c: String { "c\(id % 89)" }
    var d: String { "d\(id % 83)" }
}
let tableRows = (0..<N).map { TRow(id: $0) }

struct LongTable: View {
    @State private var selection: Int? = 0
    let height: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(n: selection ?? 0)
            Table(tableRows, selection: $selection) {
                TableColumn("A", value: \.a)
                TableColumn("B", value: \.b)
                TableColumn("C", value: \.c)
                TableColumn("D", value: \.d)
            }
            .frame(height: height)
        }
    }
}
