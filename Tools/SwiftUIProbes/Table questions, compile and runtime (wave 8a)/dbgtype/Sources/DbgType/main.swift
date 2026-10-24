// Fix attempt 2: the refining protocols re-declare the base's associated type
// to give it their own default, and a user type relies on the default.

public protocol _ValueCarrying { associatedtype Value }
public protocol ColumnLike<Value>: _ValueCarrying {
    associatedtype Value = Body.Value
    associatedtype Body: ColumnLike
    var body: Body { get }
}
public protocol RowLike<Value>: _ValueCarrying {
    associatedtype Value = Body.Value
    associatedtype Body: RowLike
    var body: Body { get }
}

extension Never: ColumnLike, RowLike {
    public typealias Value = Never
    public typealias Body = Never
    public var body: Never { fatalError() }
}

struct Leaf<V>: ColumnLike, RowLike {
    typealias Value = V
    typealias Body = Never
    var body: Never { fatalError() }
}

struct Box<Content> { var content: Content }
extension Box: _ValueCarrying where Content: _ValueCarrying { typealias Value = Content.Value }
extension Box: ColumnLike where Content: ColumnLike {
    typealias Body = Never
    var body: Never { fatalError() }
}
extension Box: RowLike where Content: RowLike {
    typealias Body = Never
    var body: Never { fatalError() }
}

struct Mine: ColumnLike {
    var body: some ColumnLike<Int> { Leaf<Int>() }
}

struct Spec<V> { var v: V? }

func specs<C: ColumnLike>(_ c: C) -> [Spec<C.Value>] { [] }
func opaque<C: ColumnLike>(_ c: C) -> some ColumnLike<C.Value> { c }

let box = Box(content: Leaf<Int>())
let result = specs(box)
let o = opaque(box)
let result2 = specs(o)
let mine: [Spec<Int>] = specs(Mine())
print(result.count, result2.count, mine.count, Mine.Value.self)
