import Foundation

func f<S: SortComparator>(_: S.Type) { print("ok", S.self) }
f(Never.self)
let ns = Locale.NumberingSystem("arab")
print(ns, Locale.current.numberingSystem)
struct P: Identifiable { var id: Int; var name: String }
let d = SortDescriptor(\P.name)
print(d.order)
