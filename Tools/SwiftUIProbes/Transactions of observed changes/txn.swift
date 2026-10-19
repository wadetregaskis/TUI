// Probe: which transaction does SwiftUI update a body under when one event writes two
// @Observable properties the body reads, one outside and one inside withAnimation?
//
// Top-level code, built alone:
//   xcrun swiftc -target arm64-apple-macos15.0 txn.swift -o "$TMPDIR/txn" && "$TMPDIR/txn" | diff txn.out -
import AppKit
import Observation
import SwiftUI

@Observable final class Model { var a = 0; var b = 0 }
final class Log { var seen: [String] = [] }

struct Probe: View {
    let model: Model
    let log: Log
    var body: some View {
        Text("\(model.a) \(model.b)")
            .transaction { t in log.seen.append("a=\(model.a) b=\(model.b) animated=\(t.animation != nil)") }
    }
}

@MainActor func run(_ name: String, _ change: (Model) -> Void) {
    let model = Model()
    let log = Log()
    let host = NSHostingView(rootView: Probe(model: model, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    log.seen.removeAll()
    change(model)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    print(name, log.seen)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    run("plain a, then animated b:") { m in m.a += 1; withAnimation(.linear(duration: 1)) { m.b += 1 } }
    run("animated b, then plain a:") { m in withAnimation(.linear(duration: 1)) { m.b += 1 }; m.a += 1 }
    run("animated b only:        ") { m in withAnimation(.linear(duration: 1)) { m.b += 1 } }
    run("plain a only:           ") { m in m.a += 1 }
    run("plain a, then empty withAnimation:") { m in m.a += 1; withAnimation(.linear(duration: 1)) {} }
    run("plain a, then animated write nobody reads:") { m in m.a += 1; withAnimation(.linear(duration: 1)) { _ = 0 } }
}
