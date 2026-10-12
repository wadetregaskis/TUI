import SwiftUI

@main
struct Probe {
    @MainActor static func main() {
        let env = EnvironmentValues()
        print("default contentTransition", env.contentTransition)
        print("is identity", env.contentTransition == .identity, "interpolate", env.contentTransition == .interpolate, "opacity", env.contentTransition == .opacity)
        print("drawingGroup", env.contentTransitionAddsDrawingGroup)
        print(ContentTransition.numericText(countsDown: true) == .numericText(countsDown: true))
        print(ContentTransition.numericText(countsDown: true) == .numericText(countsDown: false))
        print(ContentTransition.numericText(value: 3) == .numericText(value: 4))
        print(ContentTransition.numericText(value: 3) == .numericText(countsDown: false))
        print(String(describing: ContentTransition.opacity), String(describing: ContentTransition.numericText(value: 3)))
    }
}
