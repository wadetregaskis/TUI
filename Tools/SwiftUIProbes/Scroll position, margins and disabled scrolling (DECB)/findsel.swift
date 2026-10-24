import AppKit
import Foundation
import ObjectiveC

_ = dlopen("/System/Library/PrivateFrameworks/TextInput.framework/TextInput", RTLD_NOW)
_ = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_NOW); _ = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW); _ = dlopen("/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/HIToolbox", RTLD_NOW)
let sels: Set<String> = ["keyInputToKeyEquivalentMap", "localizedKeyEquivalentForInput:", "localizedKeyEquivalentDisplayName",
            "_unlocalizedKeyEquivalent", "_ti_isKeyEquivalentMirroringCandidate", "menuItemOrSubmenuNeedsShortcutLocalization"]
var imgCount: UInt32 = 0
let images = objc_copyImageNames(&imgCount)
for k in 0..<Int(imgCount) {
    let img = String(cString: images[k])
    guard img.contains("AppKit") || img.contains("TextInput") || img.contains("HIToolbox") || img.contains("UIFoundation") || img.contains("SwiftUI") else { continue }
    var n: UInt32 = 0
    guard let names = objc_copyClassNamesForImage(images[k], &n) else { continue }
    for i in 0..<Int(n) {
        let cname = names[i]
        for metaFlag in [false, true] {
            let c: AnyClass? = metaFlag ? objc_getMetaClass(cname) as? AnyClass : objc_getClass(cname) as? AnyClass
            guard let cls = c else { continue }
            var m: UInt32 = 0
            guard let ml = class_copyMethodList(cls, &m) else { continue }
            for j in 0..<Int(m) {
                let s = NSStringFromSelector(method_getName(ml[j]))
                if sels.contains(s) {
                    print("\(metaFlag ? "+" : "-")[\(String(cString: cname)) \(s)] types=\(String(cString: method_getTypeEncoding(ml[j])!)) image=\((img as NSString).lastPathComponent)")
                }
            }
            free(ml)
        }
    }
    free(names)
}
