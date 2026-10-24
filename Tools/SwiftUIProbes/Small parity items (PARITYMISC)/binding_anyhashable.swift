import SwiftUI
@MainActor func run() {
    var x = 1
    let b = Binding<Int>(get: { x }, set: { x = $0 })
    let h = Binding<AnyHashable>(b)
    print("read", h.wrappedValue)
    h.wrappedValue = AnyHashable(5)
    print("after Int 5:", x)
    h.wrappedValue = AnyHashable(Int8(7))
    print("after Int8 7:", x)
    h.wrappedValue = AnyHashable("str")
    print("after String:", x)
    print("done")
}
MainActor.assumeIsolated { run() }
