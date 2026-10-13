// T10 (2026-10-13): the key SwiftUI's LocalizedStringKey records for each kind
// of interpolated value, read from the key's stored `key` field. No view drawn.
import SwiftUI
import Foundation

func key(_ k: LocalizedStringKey) -> String {
    for c in Mirror(reflecting: k).children where c.label == "key" { return "\(c.value)" }
    return "?"
}
func show(_ label: String, _ k: LocalizedStringKey) { print("\(label)\t\(key(k))") }

let i = 5; let i8: Int8 = 5; let i16: Int16 = 5; let i32: Int32 = 5; let i64: Int64 = 5
let u: UInt = 5; let u8: UInt8 = 5; let u16: UInt16 = 5; let u32: UInt32 = 5; let u64: UInt64 = 5
let f: Float = 2.5; let d = 2.5; let cg: CGFloat = 2.5
let s = "x"; let sub = s[...]
let date = Date(timeIntervalSince1970: 0)
let attributed = AttributedString("a")
let number = NSNumber(value: 3)
let url = URL(string: "https://example.com")!

show("Int", "v \(i)")
show("Int8", "v \(i8)")
show("Int16", "v \(i16)")
show("Int32", "v \(i32)")
show("Int64", "v \(i64)")
show("UInt", "v \(u)")
show("UInt8", "v \(u8)")
show("UInt16", "v \(u16)")
show("UInt32", "v \(u32)")
show("UInt64", "v \(u64)")
show("Float", "v \(f)")
show("Double", "v \(d)")
show("CGFloat", "v \(cg)")
show("String", "v \(s)")
show("Substring", "v \(String(sub))")
show("Text", "v \(Text("t"))")
show("Image", "v \(Image(systemName: "star"))")
show("AttributedString", "v \(attributed)")
show("Date style", "v \(date, style: .date)")
show("Date format", "v \(date, format: .dateTime)")
show("Double format", "v \(d, format: .number)")
show("Int specifier %d", "v \(i, specifier: "%d")")
show("Double specifier %.2f", "v \(d, specifier: "%.2f")")
show("Int specifier %x", "v \(i, specifier: "%x")")
show("NSNumber", "v \(number)")
show("NSNumber formatter", "v \(number, formatter: NumberFormatter())")
show("URL (ReferenceConvertible)", "v \(url as URL)")
show("Date range", "v \(date...date.addingTimeInterval(60))")
show("percent literal", "100% \(i)")
show("two", "\(i) of \(d) and \(s)")
