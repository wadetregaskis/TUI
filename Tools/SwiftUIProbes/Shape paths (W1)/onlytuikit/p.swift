import TUIkit
struct Tri: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.midX, y: 0)) }
    }
}
@MainActor func f() -> some View { Circle().offset(x: 2, y: 3) }
@MainActor func g() -> OffsetShape<Circle> { Circle().offset(x: 2, y: 3) }
