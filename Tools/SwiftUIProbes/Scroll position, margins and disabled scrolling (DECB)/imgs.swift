import AppKit
import ObjectiveC
_ = dlopen("/System/Library/PrivateFrameworks/TextInput.framework/TextInput", RTLD_NOW)
var c: UInt32 = 0
let images = objc_copyImageNames(&c)
print(c)
for k in 0..<Int(c) { let s = String(cString: images[k]); if s.contains("AppKit") || s.contains("TextInput") || s.contains("HIToolbox") { print(s) } }
