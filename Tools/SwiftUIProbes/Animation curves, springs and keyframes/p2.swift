import SwiftUI

@main
struct Probe {
    @MainActor static func main() {
        let animations: [Animation] = [
            .easeInOut, .linear(duration: 2), .spring(duration: 0.5, bounce: 0.3),
            .easeIn.delay(1).speed(2).repeatCount(3, autoreverses: true),
            .timingCurve(0.1, 0.2, 0.3, 0.4, duration: 1),
            .bouncy, .default.logicallyComplete(after: 0.2),
        ]
        for a in animations {
            print("description:", a.description)
            print("debugDescription:", a.debugDescription)
            let mirror = Mirror(reflecting: a)
            print("mirror displayStyle:", String(describing: mirror.displayStyle), "children:", mirror.children.map { "\($0.label ?? "_")=\($0.value)" })
            print("---")
        }
    }
}
