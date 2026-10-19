// B-D5G-8: the threshold each of SwiftUI's scroll transition configurations
// starts with. The configuration holds it as data, so a dump reads it.
// Top-level code, built alone.

import SwiftUI

func dump(_ name: String, _ c: ScrollTransitionConfiguration) {
    var s = ""
    Swift.dump(c, to: &s)
    print("== \(name)\n\(s)")
}
dump("interactive", .interactive)
dump("interactive.threshold(.visible)", .interactive.threshold(.visible))
dump("interactive.threshold(.visible(1))", .interactive.threshold(.visible(1)))
dump("interactive.threshold(.visible(0.5))", .interactive.threshold(.visible(0.5)))
dump("interactive.threshold(.centered)", .interactive.threshold(.centered))
dump("interactive.threshold(.hidden)", .interactive.threshold(.hidden))
dump("animated", .animated)
dump("animated.threshold(.visible)", .animated.threshold(.visible))
dump("identity", .identity)
dump("animated(.linear)", .animated(.linear))
dump("animated()", .animated())
dump("interactive(timingCurve: .linear)", .interactive(timingCurve: .linear))
dump("animated.animation(.linear)", .animated.animation(.linear))
