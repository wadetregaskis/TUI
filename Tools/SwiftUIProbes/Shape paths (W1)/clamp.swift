import SwiftUI
@main struct P { static func main() {
  for s in [CGSize(width: 8, height: 2), CGSize(width: 2, height: 8), CGSize(width: 12, height: 3), CGSize(width: 7, height: 7)] {
    print(s, Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 10), cornerSize: s, style: .circular).description)
  }
  print("uneven big", Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 10), cornerRadii: .init(topLeading: 8, bottomLeading: 0, bottomTrailing: 0, topTrailing: 8), style: .circular).description)
  print("uneven big2", Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 10), cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 3), style: .circular).description)
}}
