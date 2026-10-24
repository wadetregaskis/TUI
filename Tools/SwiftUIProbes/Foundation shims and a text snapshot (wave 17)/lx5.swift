import Foundation
let f = NumberFormatter()
var o: AnyObject? = nil
var e: NSString? = nil
let ok = f.getObjectValue(&o, for: "12", errorDescription: nil)
let s = f.string(for: 12)
func g<T: ReferenceConvertible>(_ t: T) {}
let n: NSObject = NSNumber(value: 1)
print(ok, s as Any, n)
