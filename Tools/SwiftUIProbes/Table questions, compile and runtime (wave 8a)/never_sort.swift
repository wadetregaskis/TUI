import Foundation
func f<S: SortComparator>(_: S.Type) { print("ok", S.self) }
f(Never.self)
