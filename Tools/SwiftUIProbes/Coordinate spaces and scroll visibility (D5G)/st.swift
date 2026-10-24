import SwiftUI
import AppKit

@MainActor final class Log { static var phases: [String: [Int: String]] = [:] }

struct Rows: View {
    let tag: String
    let configuration: ScrollTransitionConfiguration?
    @State var pos = ScrollPosition(y: 55)
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { i in
                    if let configuration {
                        Color.gray.frame(height: 20)
                            .scrollTransition(configuration) { content, phase in
                                MainActor.assumeIsolated {
                                    Log.phases[tag, default: [:]][i] = (Log.phases[tag]?[i].map { $0 + "," } ?? "") + "\(phase)"
                                }
                                return content.opacity(phase.isIdentity ? 1 : 0.5)
                            }
                    } else {
                        Color.gray.frame(height: 20)
                            .scrollTransition { content, phase in
                                MainActor.assumeIsolated {
                                    Log.phases[tag, default: [:]][i] = (Log.phases[tag]?[i].map { $0 + "," } ?? "") + "\(phase)"
                                }
                                return content.opacity(phase.isIdentity ? 1 : 0.5)
                            }
                    }
                }
            }
        }
        .scrollPosition($pos)
        .frame(width: 100, height: 100)
    }
}

@MainActor func run(_ tag: String, _ c: ScrollTransitionConfiguration?) {
    let h = NSHostingView(rootView: AnyView(Rows(tag: tag, configuration: c)))
    h.frame = NSRect(origin: .zero, size: CGSize(width: 100, height: 100))
    h.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    h.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    let rows = Log.phases[tag] ?? [:]
    print("==", tag)
    for i in rows.keys.sorted() { print("row", i, "y", 20 * i - 55, ":", rows[i]!) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            run("default", nil)
            run("animated", .animated)
            run("interactive", .interactive)
            run("animated-centered", .animated.threshold(.centered))
        }
    }
}
