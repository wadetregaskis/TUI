import Foundation

#if canImport(FoundationEssentials)
print("canImport(FoundationEssentials): yes")
#else
print("canImport(FoundationEssentials): no")
#endif

// Which bound a discrete format moves for a Range<Date> input, and what a
// Duration.TimeFormatStyle's discrete boundaries are.
let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
let en = Locale(identifier: "en_US")
if #available(macOS 15, *) {
    let f = Date.ComponentsFormatStyle(style: .wide, locale: en, calendar: Calendar(identifier: .gregorian))
    let r = base..<base.addingTimeInterval(125.5)
    func show(_ x: Range<Date>?) -> String {
        guard let x else { return "nil" }
        return "\(x.lowerBound.timeIntervalSince(base))..<\(x.upperBound.timeIntervalSince(base))"
    }
    print("components after", show(f.discreteInput(after: r)), "before", show(f.discreteInput(before: r)))
    let t = Duration.TimeFormatStyle(pattern: .minuteSecond).locale(en)
    for d in [Duration.seconds(125.5), .seconds(125.2), .seconds(-125.5), .seconds(0)] {
        print("time pattern", d, t.format(d), "after", t.discreteInput(after: d) as Any, "before", t.discreteInput(before: d) as Any)
    }
    let df = Date.FormatStyle(date: .omitted, time: .standard).locale(en)
    print("dateTime after", df.discreteInput(after: base.addingTimeInterval(0.3)).map { $0.timeIntervalSince(base) } as Any)
    let df2 = Date.FormatStyle(date: .omitted, time: .shortened).locale(en)
    print("shortened after", df2.discreteInput(after: base.addingTimeInterval(0.3)).map { $0.timeIntervalSince(base) } as Any)
}
