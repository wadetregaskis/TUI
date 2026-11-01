
// ---- Shared by both frameworks, unchanged. Scenario picked by the BENCH environment variable. ----
let benchEnv = ProcessInfo.processInfo.environment
let scenario = benchEnv["BENCH"] ?? "tree-leaf"
let R = Int(benchEnv["BENCH_R"] ?? "") ?? 48
let C = Int(benchEnv["BENCH_C"] ?? "") ?? 40
let N = Int(benchEnv["BENCH_N"] ?? "") ?? 10_000
let D = Int(benchEnv["BENCH_D"] ?? "") ?? 100
let BURN_MS = Int(benchEnv["BENCH_BURN_MS"] ?? "") ?? 50
let TICK_MS = Int(benchEnv["BENCH_TICK_MS"] ?? "") ?? 16
let LAYERS = Int(benchEnv["BENCH_LAYERS"] ?? "") ?? 30

/// A marker for `n` whose 8 cells ALL differ from those of n±1, so a cell-diffing writer has to send the whole
/// marker and the driver can find it verbatim in the byte stream.
func marker(_ n: Int) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var s = "K="
    for pos in 0..<8 { s.append(letters[(n + pos * 3) % 26]) }
    return s
}

struct Marker: View {
    let n: Int
    var body: some View { Text(marker(n)) }
}

struct Cell: View {
    let r: Int
    let c: Int
    let t: Int
    var body: some View {
        Text("\((r + t) % 10)\((c + t) % 10)ab")
    }
}

struct LeafCounter: View {
    @State private var n = 0
    var body: some View {
        HStack(spacing: 1) {
            Button("Go") { n += 1 }
            Marker(n: n)
        }
    }
}

struct Row: View {
    let r: Int
    let t: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<C, id: \.self) { c in Cell(r: r, c: c, t: t) }
        }
    }
}

/// (a) one leaf with its own @State changes; 1,920 cells stay as they are.
struct TreeLeaf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LeafCounter()
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: 0) }
        }
    }
}

/// (a) the state lives at the root, and only one leaf reads it; every body below the root runs.
struct TreeRoot: View {
    @State private var n = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: 0) }
        }
    }
}

@MainActor @Observable final class BenchModel { var n = 0 }

struct ObsLeaf: View {
    let model: BenchModel
    var body: some View { Marker(n: model.n) }
}

/// (a) an @Observable property read by one leaf, written by a button elsewhere.
struct TreeObservable: View {
    @State private var model = BenchModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { model.n += 1 }
                ObsLeaf(model: model)
            }
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: 0) }
        }
    }
}

/// (a) worst case: every cell's text changes.
struct TreeAll: View {
    @State private var n = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: n) }
        }
    }
}

/// (b) a list of N rows, selection moved with the arrow keys.
struct LongList: View {
    @State private var selection: Int? = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(n: selection ?? 0)
            List(selection: $selection) {
                ForEach(0..<N, id: \.self) { i in
                    Text("Row \(i) some text to fill the row").tag(i)
                }
            }
        }
    }
}

/// (b) a ScrollView of a lazy stack, driven with the wheel.
struct LongScroll: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<N, id: \.self) { i in
                    Text("Row \(i) some text to fill the row")
                }
            }
        }
    }
}

func burn(ms: Int) {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: .milliseconds(ms))
    var x = 0
    while clock.now < end { x &+= 1 }
    if x == -1 { print(x) }
}

struct SlowBody: View {
    let t: Int
    var body: some View {
        let _ = burn(ms: BURN_MS)
        Text("t=\(t)")
    }
}

/// (c1) a body that takes BURN_MS, re-evaluated by a ticker, beside a button.
struct LatSlowBody: View {
    @State private var n = 0
    @State private var t = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            SlowBody(t: t)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(TICK_MS))
                t += 1
            }
        }
    }
}

/// (c2) every cell changes on a ticker: body and tail both heavy.
struct LatHeavyTree: View {
    @State private var n = 0
    @State private var t = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: t) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(TICK_MS))
                t += 1
            }
        }
    }
}

struct BlendStack: View {
    let t: Int
    var body: some View {
        ZStack {
            ForEach(0..<LAYERS, id: \.self) { i in
                Rectangle()
                    .fill(LinearGradient(colors: [Color.red, Color.blue], startPoint: .leading, endPoint: .trailing))
                    .opacity(0.02 + Double((t + i) % 10) / 100)
                    .blendMode(.screen)
            }
        }
    }
}

/// (c3) cheap bodies, an expensive tail: LAYERS full-screen gradients blended per cell, on a ticker.
/// This is the case an off-main frame tail exists for.
struct LatBlend: View {
    @State private var n = 0
    @State private var t = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            BlendStack(t: t)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(TICK_MS))
                t += 1
            }
        }
    }
}

/// (d) D levels of VStack, then a leaf with state.
struct Nest: View {
    let d: Int
    var body: some View {
        if d == 0 {
            LeafCounter()
        } else {
            VStack(spacing: 0) { AnyView(Nest(d: d - 1)) }
        }
    }
}

/// (d) the same with no AnyView: a recursive struct whose body's type names the struct.
struct NestPlain: View {
    let d: Int
    var body: some View {
        VStack(spacing: 0) {
            if d == 0 {
                LeafCounter()
            } else {
                NestPlain(d: d - 1)
            }
        }
    }
}

/// (b) the list again, from data rather than a ForEach in a builder.
struct LongListData: View {
    @State private var selection: Int? = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(n: selection ?? 0)
            List(0..<N, id: \.self, selection: $selection) { i in
                Text("Row \(i) some text to fill the row")
            }
        }
    }
}

/// (b) with a stated height, as SwiftTUI's own perf scenario gives its table.
struct FramedList: View {
    @State private var selection: Int? = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Marker(n: selection ?? 0)
            List(0..<N, id: \.self, selection: $selection) { i in
                Text("Row \(i) some text to fill the row")
            }
            .frame(height: 44)
        }
    }
}

struct FramedTable: View {
    var body: some View { LongTable(height: 44) }
}

/// (e) a repeating animation of the opacity of a whole screen of cells.
struct AnimOpacity: View {
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<R, id: \.self) { r in Row(r: r, t: 0) }
        }
        .foregroundStyle(Color.green)
        .opacity(on ? 1 : 0.2)
        .onAppear { startForever { on = true } }
    }
}

/// (e) a repeating animation of the position of many small views.
struct AnimMove: View {
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<R, id: \.self) { r in
                Text("moving row \(r)").offset(x: on ? 60 : 0, y: 0)
            }
        }
        .onAppear { startForever { on = true } }
    }
}

/// (e) a ticker drives a whole screen of coloured cells.
struct AnimTick: View {
    @State private var t = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<R, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<(C * 5), id: \.self) { c in
                        Text("x").foregroundStyle(cellColor(r, c, t))
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(TICK_MS))
                t += 1
            }
        }
    }
}

func cellColor(_ r: Int, _ c: Int, _ t: Int) -> Color {
    switch (r + c + t) % 4 {
    case 0: return Color.red
    case 1: return Color.green
    case 2: return Color.blue
    default: return Color.yellow
    }
}

struct IdleText: View {
    var body: some View { Text("Hello, idle") }
}

struct BenchRoot: View {
    var body: some View {
        switch scenario {
        case "tree-leaf": TreeLeaf()
        case "tree-root": TreeRoot()
        case "tree-obs": TreeObservable()
        case "tree-all": TreeAll()
        case "list": LongList()
        case "table": LongTable(height: nil)
        case "scroll": LongScroll()
        case "scroll-varied": ScrollVaried()
        case "lat-slowbody": LatSlowBody()
        case "lat-heavy": LatHeavyTree()
        case "lat-blend": LatBlend()
        case "deep": Nest(d: D)
        case "deep-plain": NestPlain(d: D)
        case "list-data": LongListData()
        case "list-framed": FramedList()
        case "fan-leaf": FanLeaf()
        case "slow-sibling": SlowSibling()
        case "slow-sibling-parent": SlowSiblingParent()
        case "table-framed": FramedTable()
        case "anim-opacity": AnimOpacity()
        case "anim-move": AnimMove()
        case "anim-tick": AnimTick()
        case "idle-text": IdleText()
        default: Text("unknown scenario \(scenario)")
        }
    }
}

/// A row sharing nothing with its neighbours, so a diff cannot save anything and only moving the band can.
func variedRow(_ i: Int) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    var x = UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15
    var s = ""
    for _ in 0..<190 {
        x = x &* 0xBF58_476D_1CE4_E5B9 &+ 7
        s.append(letters[Int((x >> 33) % 26)])
    }
    return s
}

struct ScrollVaried: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<N, id: \.self) { i in
                    Text(variedRow(i))
                }
            }
        }
    }
}


/// A body that takes BURN_MS and depends on nothing that ever changes.
struct SlowStatic: View {
    var body: some View {
        let _ = burn(ms: BURN_MS)
        Text("I am slow and never change")
    }
}

/// (retained graph's own case) a leaf with state beside expensive siblings whose inputs never change:
/// does a frame for the leaf run their bodies again?
struct SlowSibling: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LeafCounter()
            SlowStatic()
            SlowStatic()
        }
    }
}

/// The same, with the state in the parent: the parent's body runs, its other children's inputs do not change.
struct SlowSiblingParent: View {
    @State private var n = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Button("Go") { n += 1 }
                Marker(n: n)
            }
            SlowStatic()
            SlowStatic()
        }
    }
}


/// A static tree with no ForEach: 4^depth leaves under composite views that take nothing that changes.
/// Nothing here is memoized on the way by a ForEach row, so it shows what a frame does to plain siblings.
struct Fan: View {
    let d: Int
    var body: some View {
        if d == 0 {
            Text("ab")
        } else if d % 2 == 1 {
            HStack(spacing: 1) { Fan(d: d - 1); Fan(d: d - 1); Fan(d: d - 1); Fan(d: d - 1) }
        } else {
            VStack(alignment: .leading, spacing: 0) { Fan(d: d - 1); Fan(d: d - 1); Fan(d: d - 1); Fan(d: d - 1) }
        }
    }
}

/// (a) one leaf with state beside the static Fan tree.
struct FanLeaf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LeafCounter()
            Fan(d: D)
        }
    }
}
