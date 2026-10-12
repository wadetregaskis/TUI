@_silgen_name("swift_reflectionMirror_recursiveCount")
func runtimeRecursiveFieldCount(_: Any.Type) -> Int
enum E { case a(Int, String), b(Double), c }
struct S { var x: Int; var y: String }
print("enum E fields:", runtimeRecursiveFieldCount(E.self))
print("struct S fields:", runtimeRecursiveFieldCount(S.self))
