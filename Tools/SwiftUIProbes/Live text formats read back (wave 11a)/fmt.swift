import SwiftUI
import Foundation

let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
func at(_ s: Double) -> Date { base.addingTimeInterval(s) }
var en = Locale(identifier: "en_US")
func show<F: FormatStyle>(_ label: String, _ f: F, _ x: F.FormatInput) where F.FormatOutput == AttributedString {
    print(label, "→", String(f.locale(en).format(x).characters).debugDescription)
}
// Timer counting down to base+3725 (1h 2m 5s)
let down = SystemFormatStyle.Timer(countingDownIn: base..<at(3725))
for t in [0.0, 1, 59.5, 3600, 3724, 3725, 4000] { show("timer down t=\(t)", down, at(t)) }
let downNoHours = SystemFormatStyle.Timer(countingDownIn: base..<at(3725), showsHours: false)
show("timer down noHours t=0", downNoHours, at(0))
let up = SystemFormatStyle.Timer(countingUpIn: base..<at(100))
for t in [-5.0, 0, 5, 65, 99, 150] { show("timer up t=\(t)", up, at(t)) }
let upPrec = SystemFormatStyle.Timer(countingUpIn: base..<at(100), maxPrecision: .milliseconds(10))
show("timer up prec10ms t=5.678", upPrec, at(5.678))
let upFields = SystemFormatStyle.Timer(countingUpIn: base..<at(100000), maxFieldCount: 2)
show("timer up maxField2 t=3725", upFields, at(3725))
let sw = SystemFormatStyle.Stopwatch(startingAt: base)
for t in [0.0, 1.234, 65.5, 3725.25] { show("stopwatch t=\(t)", sw, at(t)) }
let swH = SystemFormatStyle.Stopwatch(startingAt: base, showsHours: true, maxPrecision: .seconds(1))
show("stopwatch hours sec t=65.5", swH, at(65.5))
let ref = SystemFormatStyle.DateReference(to: base)
for t in [-90000.0, -3700, -125, -30, -1, 0, 1, 30, 125, 3700, 90000, 400000] { show("reference t=\(t)", ref, at(t)) }
let refFields = SystemFormatStyle.DateReference(to: base, allowedFields: [.hour, .minute, .second], maxFieldCount: 2)
for t in [-3725.0, 3725] { show("reference h:m:s max2 t=\(t)", refFields, at(t)) }
let off = SystemFormatStyle.DateOffset(to: base)
for t in [-3725.0, -30, 0, 30, 3725, 90000] { show("offset t=\(t)", off, at(t)) }
let offSign = SystemFormatStyle.DateOffset(to: base, sign: .never)
show("offset never t=-30", offSign, at(-30))
show("offset never t=30", offSign, at(30))
print("discrete after", down.discreteInput(after: at(10.3)) as Any, "before", down.discreteInput(before: at(10.3)) as Any)
print("ref discrete after t=125", ref.discreteInput(after: at(125)).map { $0.timeIntervalSince(base) } as Any)
print("ref discrete after t=30", ref.discreteInput(after: at(30)).map { $0.timeIntervalSince(base) } as Any)
print("ref discrete after t=3700", ref.discreteInput(after: at(3700)).map { $0.timeIntervalSince(base) } as Any)
print("json", String(data: try! JSONEncoder().encode(down), encoding: .utf8)!)
