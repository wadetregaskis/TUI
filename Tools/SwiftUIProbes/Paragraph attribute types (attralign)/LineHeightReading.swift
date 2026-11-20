// What of Core Text's `AttributedString.LineHeight` (macOS 26) TUI could read
// back, for A-ATTRED-3's crude line height (a factor of 2 = a blank row between
// drawn rows). Type-checked by probe.sh; it can only be RUN on macOS 26, which
// the development Mac (macOS 15.8) is not, so what each way returns is not
// measured. The 26.2 SDK's interface declares the type's makers (`multiple(factor:)`,
// `leading(increase:)`, `exact(points:)`, `normal`, `tight`, `loose`,
// `variable`), `==`, `hash(into:)` and Codable, and no accessor for a factor.
import CoreText
import Foundation

@available(macOS 26, *)
enum LineHeightReading {
    /// 1. Public API only: compare with values made from a grid of factors. Exact
    ///    for a value on the grid; any other `multiple(factor:)` is unreadable,
    ///    and so is every `leading`/`exact` value (a grid has no points anyway).
    static func rowsByComparison(_ height: AttributedString.LineHeight) -> Int? {
        for tenths in stride(from: 10, through: 40, by: 5) {
            let factor = Double(tenths) / 10
            if height == .multiple(factor: factor) { return max(1, Int(factor.rounded())) }
        }
        return nil
    }

    /// 2. Codable: encode and read the factor out of whatever the encoding is.
    ///    The encoding is not documented; what it prints on macOS 26 is not
    ///    measured. A test on the macOS 26 lane would have to pin it.
    static func encoded(_ height: AttributedString.LineHeight) throws -> String {
        String(decoding: try JSONEncoder().encode(height), as: UTF8.self)
    }

    /// 3. Reflection: the stored properties' labels and values, private and
    ///    unversioned. Not measured.
    static func reflected(_ height: AttributedString.LineHeight) -> [String] {
        Mirror(reflecting: height).children.map { "\($0.label ?? "_"): \($0.value)" }
    }
}
