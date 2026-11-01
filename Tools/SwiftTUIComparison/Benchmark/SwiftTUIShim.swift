
@main struct BenchApp: App {
    var body: some Scene { WindowGroup { BenchRoot() } }
}

@MainActor func startForever(_ change: () -> Void) {
    withAnimation(.linear(duration: .seconds(1)).repeatForever(autoreverses: true)) { change() }
}

struct LongTable: View {
    @State private var selection: Int? = 0
    let height: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(n: selection ?? 0)
            Table(
                0..<N, id: \.self, selection: $selection,
                columns: [TableColumn("A"), TableColumn("B"), TableColumn("C"), TableColumn("D")]
            ) { id in
                Text("Row \(id)")
                Text("b\(id % 97)")
                Text("c\(id % 89)")
                Text("d\(id % 83)")
            }
            .frame(height: height)
        }
    }
}
