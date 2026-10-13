import Darwin

// DYNVCLAIM (2026-10-12), angle "swiftui-first": what a creation stamp in
// TUIkit's StateBacking.init would cost per @State constructed. The init
// allocates the backing and its box (two objects), as State(wrappedValue:)
// does today; each variant adds one way of reading "when was this made".
// macOS arm64, -O. Unmeasured anywhere else.

final class Box<Value> { var value: Value; init(_ v: Value) { value = v } }

final class Plain<Value> {
    let defaultValue: Value
    var box: Box<Value>
    var isBound = false
    init(_ v: Value) { defaultValue = v; box = Box(v) }
}

final class Stamped<Value> {
    let defaultValue: Value
    var box: Box<Value>
    var isBound = false
    let stamp: UInt64
    init(_ v: Value, stamp: UInt64) { defaultValue = v; box = Box(v); self.stamp = stamp }
}

nonisolated(unsafe) var passCounter: UInt64 = 7

enum Local {
    @TaskLocal static var pass: UInt64?
}

nonisolated(unsafe) var kept: AnyObject?
@inline(never) func sink(_ x: AnyObject) { kept = x }

func time(_ label: String, _ n: Int, _ body: () -> Void) {
    // Warm up, then best of 5.
    body()
    var best = UInt64.max
    for _ in 0..<5 {
        let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        body()
        let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        best = min(best, t1 - t0)
    }
    let hundredths = (best * 100) / UInt64(n)
    print("\(label): \(hundredths / 100).\(hundredths % 100 < 10 ? "0" : "")\(hundredths % 100) ns per init")
}

let n = 2_000_000
time("baseline (backing + box)", n) { for i in 0..<n { sink(Plain(i)) } }
time("+ clock_gettime_nsec_np(UPTIME_RAW)", n) {
    for i in 0..<n { sink(Stamped(i, stamp: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))) }
}
time("+ mach_absolute_time", n) { for i in 0..<n { sink(Stamped(i, stamp: mach_absolute_time())) } }
time("+ SuspendingClock.now (as MonotonicClock)", n) {
    for i in 0..<n {
        let c = SuspendingClock.now
        sink(Stamped(i, stamp: UInt64(truncatingIfNeeded: c.hashValue)))
    }
}
time("+ pthread_main_np + global load", n) {
    for i in 0..<n { sink(Stamped(i, stamp: pthread_main_np() != 0 ? passCounter : 0)) }
}
time("+ TaskLocal read (unbound)", n) { for i in 0..<n { sink(Stamped(i, stamp: Local.pass ?? 0)) } }
Local.$pass.withValue(3) {
    time("+ TaskLocal read (bound once)", n) { for i in 0..<n { sink(Stamped(i, stamp: Local.pass ?? 0)) } }
}
