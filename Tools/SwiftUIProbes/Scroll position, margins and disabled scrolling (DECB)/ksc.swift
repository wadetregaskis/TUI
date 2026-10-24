import Foundation
import ObjectiveC
_ = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
_ = dlopen("/System/Library/PrivateFrameworks/TextInput.framework/TextInput", RTLD_NOW)
for metaFlag in [false, true] {
    let c: AnyClass? = metaFlag ? objc_getMetaClass("NSKeyboardShortcut") as? AnyClass : objc_getClass("NSKeyboardShortcut") as? AnyClass
    guard let cls = c else { print("no class"); continue }
    var m: UInt32 = 0
    if let ml = class_copyMethodList(cls, &m) {
        for j in 0..<Int(m) { print(metaFlag ? "+" : "-", NSStringFromSelector(method_getName(ml[j])), String(cString: method_getTypeEncoding(ml[j])!)) }
        free(ml)
    }
}
for sym in ["TIKeyEquivalentMirroringCandidatesMap", "ti_isKeyEquivalentMirroringCandidate", "_ti_isKeyEquivalentMirroringCandidate", "keyInputToKeyEquivalentMap"] {
    let h = dlopen(nil, RTLD_NOW)
    print(sym, dlsym(h, sym) != nil)
}
