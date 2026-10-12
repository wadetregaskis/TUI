import SwiftUI
import AppKit

struct Box: View {
    let name: String; var w: CGFloat = 20; var h: CGFloat = 10
    var body: some View { Color.red.frame(width: w, height: h).probe(name) }
}

struct Content: View {
    var body: some View {
        Box(name: "a")
        Spacer()
        Box(name: "b")
    }
}

struct GuideContent: View {
    var body: some View {
        Box(name: "a", w: 60)
        Box(name: "b").alignmentGuide(.leading) { _ in -15 }
        Box(name: "c").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
    }
}

struct SpacerMin: View {
    var body: some View {
        Box(name: "a")
        Spacer(minLength: 30)
        Box(name: "b")
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let s = CGSize(width: 200, height: 60)
            measure("direct hstack spacer", size: s, HStack(spacing: 5) { Content() })
            measure("proxied hstack spacer", size: s, HStack(spacing: 5) { ForEach(subviews: Content()) { $0 } })
            measure("proxied group-subviews spacer", size: s, HStack(spacing: 5) { Group(subviews: Content()) { sv in ForEach(sv) { $0 } } })
            measure("proxied single subview spacer", size: s, HStack(spacing: 5) { Group(subviews: Content()) { sv in sv[0]; sv[1]; sv[2] } })
            measure("direct hstack spacer fixed", size: s, HStack(spacing: 5) { Content() }.fixedSize())
            measure("proxied hstack spacer fixed", size: s, HStack(spacing: 5) { ForEach(subviews: Content()) { $0 } }.fixedSize())
            measure("direct min30 fixed", size: s, HStack(spacing: 5) { SpacerMin() }.fixedSize())
            measure("proxied min30 fixed", size: s, HStack(spacing: 5) { ForEach(subviews: SpacerMin()) { $0 } }.fixedSize())
            measure("direct vstack spacer", size: CGSize(width: 60, height: 200), VStack(spacing: 5) { Content() })
            measure("proxied vstack spacer", size: CGSize(width: 60, height: 200), VStack(spacing: 5) { ForEach(subviews: Content()) { $0 } })
            measure("proxied spacer with padding", size: s, HStack(spacing: 5) { ForEach(subviews: Content()) { $0.padding(0) } })
            measure("direct guides", size: CGSize(width: 200, height: 100), VStack(alignment: .leading, spacing: 5) { GuideContent() })
            measure("proxied guides", size: CGSize(width: 200, height: 100), VStack(alignment: .leading, spacing: 5) { ForEach(subviews: GuideContent()) { $0 } })
            measure("direct guides center", size: CGSize(width: 200, height: 100), VStack(alignment: .center, spacing: 5) { GuideContent() })
            measure("proxied guides center", size: CGSize(width: 200, height: 100), VStack(alignment: .center, spacing: 5) { ForEach(subviews: GuideContent()) { $0 } })
            measure("proxied guides padded", size: CGSize(width: 200, height: 100), VStack(alignment: .leading, spacing: 5) { ForEach(subviews: GuideContent()) { $0.padding(.leading, 4) } })
            measure("proxied guides then proxy guide", size: CGSize(width: 200, height: 100), VStack(alignment: .leading, spacing: 5) { ForEach(subviews: GuideContent()) { $0.alignmentGuide(.leading) { _ in -40 } } })
        }
    }
}
