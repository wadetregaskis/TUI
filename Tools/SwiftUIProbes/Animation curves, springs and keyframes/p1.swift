import SwiftUI

@main
struct Probe {
    @MainActor static func main() {
        print("opacity.hasMotion", OpacityTransition.properties.hasMotion)
        print("move.hasMotion", MoveTransition.properties.hasMotion)
        print("offset.hasMotion", OffsetTransition.properties.hasMotion)
        print("scale.hasMotion", ScaleTransition.properties.hasMotion)
        print("slide.hasMotion", SlideTransition.properties.hasMotion)
        print("push.hasMotion", PushTransition.properties.hasMotion)
        print("identity.hasMotion", IdentityTransition.properties.hasMotion)
        print("blur.hasMotion", BlurReplaceTransition.properties.hasMotion)
        print("asym(op,op).hasMotion", AsymmetricTransition<OpacityTransition, OpacityTransition>.properties.hasMotion)
        print("asym(op,move).hasMotion", AsymmetricTransition<OpacityTransition, MoveTransition>.properties.hasMotion)
        let s: ScaleTransition = .scale
        print("scale default", s.scale, s.anchor)
        let s2: ScaleTransition = .scale(0.5)
        print("scale(0.5)", s2.scale, s2.anchor)
        print("phase values", TransitionPhase.willAppear.value, TransitionPhase.identity.value, TransitionPhase.didDisappear.value)
        print(type(of: OpacityTransition().combined(with: MoveTransition(edge: .top))))
        print(type(of: OpacityTransition().animation(.default)))
        print(type(of: OpacityTransition().combined(with: OpacityTransition())))
        let o: OffsetTransition = .offset(x: 3, y: 4)
        print("offset", o.offset)
        let m: MoveTransition = .move(edge: .leading)
        print("move", m.edge)
        let p: PushTransition = .push(from: .top)
        print("push", p.edge)
        print("opacity.properties == default?", OpacityTransition.properties.hasMotion == TransitionProperties().hasMotion)
        print("TransitionProperties() hasMotion", TransitionProperties().hasMotion)
        let combinedProps = type(of: OpacityTransition().combined(with: MoveTransition(edge: .top))).properties
        print("combined(op, move) hasMotion", combinedProps.hasMotion)
        let animProps = type(of: MoveTransition(edge: .top).animation(.default)).properties
        print("move.animation hasMotion", animProps.hasMotion)
    }
}
