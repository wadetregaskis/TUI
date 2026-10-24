import Foundation
import ObjectiveC
import Carbon
_ = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
let isCand = NSSelectorFromString("_ti_isKeyEquivalentMirroringCandidate")
let mirror = NSSelectorFromString("_ti_keyEquivalentMirroring")
typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
typealias ObjFn = @convention(c) (AnyObject, Selector) -> AnyObject?
let impB = unsafeBitCast(class_getMethodImplementation(NSString.self, isCand)!, to: BoolFn.self)
let impO = unsafeBitCast(class_getMethodImplementation(NSString.self, mirror)!, to: ObjFn.self)
var pairs: [String] = []
for u in 0x20..<0x3000 {
    guard let sc = Unicode.Scalar(u) else { continue }
    let s = NSString(string: String(Character(sc)))
    if impB(s, isCand) {
        let m = impO(s, mirror) as? String ?? "nil"
        pairs.append("U+\(String(u, radix: 16, uppercase: true)) \(String(Character(sc))) -> \(m)")
    }
}
print("candidates:", pairs.count); pairs.forEach { print($0) }
// current layout (read-only)
if let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(), let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
    print("current layout:", Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue())
}
let cls: AnyClass = objc_getClass("NSKeyboardShortcut") as! AnyClass
let sel = NSSelectorFromString("localizedKeyEquivalentForInput:")
typealias LFn = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
let lImp = unsafeBitCast(method_getImplementation(class_getClassMethod(cls, sel)!), to: LFn.self)
var changed: [String] = []
for ch in "[]{}()<>;:'\"\\|,./?`~!@#$%^&*-_=+0123456789abcdefghijklmnopqrstuvwxyz" {
    let r = lImp(cls, sel, NSString(string: String(ch)))
    let rs = (r as? String) ?? String(describing: r)
    if rs != String(ch) { changed.append("\(ch) -> \(rs)") }
}
print("localizedKeyEquivalentForInput changes under current layout:", changed)
