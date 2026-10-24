@MainActor public protocol View { associatedtype Body: View; var body: Body { get } }
extension Never: View { public var body: Never { fatalError() } }
@MainActor public protocol Animatable { var data: Double { get set } }
public nonisolated protocol Shape: Sendable, Animatable, View {
    func path(in rect: Double) -> [Double]
}
extension Shape {
    public var body: Wrapper<Self> { Wrapper(shape: self) }
}
public struct Wrapper<S: Shape>: View {
    let shape: S
    public var body: Never { fatalError() }
}
public struct Rect: Shape {
    public init() {}
    public func path(in rect: Double) -> [Double] { [rect] }
    public var data: Double { get { 0 } set {} }
}
struct Key { static let value = Rect() }
func nonisolatedUse() -> [Double] { Rect().path(in: 2) }
struct Custom: Shape {
    var data: Double = 0
    func path(in rect: Double) -> [Double] { [rect * 2] }
}
nonisolated func useCustom() -> [Double] { Custom().path(in: 1) }
@MainActor func render<S: Shape>(_ s: S) -> [Double] { s.path(in: 3) }
