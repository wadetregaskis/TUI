import SwiftUI

@main struct Main {
    static func main() {
        print("sectionHeaders", PinnedScrollableViews.sectionHeaders.rawValue)
        print("sectionFooters", PinnedScrollableViews.sectionFooters.rawValue)
        print("empty", PinnedScrollableViews().rawValue)
        print("both", PinnedScrollableViews([.sectionHeaders, .sectionFooters]).rawValue)
    }
}
