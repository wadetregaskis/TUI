//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRColorRewrite+NumericReading.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension SGRColorRewrite {
    /// ``readingColors(_:_:)`` for the sequence every row is made of — `ESC[`,
    /// decimal parameters separated by `;`, `m` — read from its bytes, with no
    /// `[String]` of parameters: `true` when it was that shape and its colours
    /// are reported, `false`, having reported nothing, when it was not.
    ///
    /// The opacity blend reads the colours of every escape of every row it
    /// takes apart, and splitting each into strings first was most of what the
    /// read cost (2026-10-26: `readingColors` 4.1% of a frame of `translucent
    /// --variant material`, `split(separator:)` and the strings it made among
    /// the largest parts). Anything else — a colon sub-parameter form, a sign,
    /// a number too long to be a code — returns `false` for the general reading,
    /// which takes it exactly as before.
    ///
    /// The same reading as the general one, parameter for parameter: an empty
    /// parameter is 0; `38;5;n` and `38;2;r;g;b` (and `48`'s) are read only where
    /// the selector is the single digit `5` or `2`, as the general reading
    /// compares it as text, and a component outside 0…255 leaves the colour
    /// unread and moves on by one.
    static func readingNumericColors(_ sequence: String, _ report: (ColorSlot, Color?) -> Void) -> Bool {
        var sequence = sequence
        return sequence.withUTF8 { bytes in
            guard bytes.count >= 3, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[bytes.count - 1] == 0x6D else {
                return false
            }
            let body = UnsafeBufferPointer(rebasing: bytes[2..<(bytes.count - 1)])
            var count = 1
            var digits = 0
            for byte in body {
                if byte == 0x3B {  // ';'
                    count += 1
                    digits = 0
                } else if byte >= 0x30, byte <= 0x39, digits < 9 {
                    digits += 1
                } else {
                    return false
                }
            }
            return withUnsafeTemporaryAllocation(of: Parameter.self, capacity: count) { parameters in
                var index = 0
                var current = Parameter(value: 0, digits: 0)
                for byte in body {
                    if byte == 0x3B {
                        parameters.initializeElement(at: index, to: current)
                        index += 1
                        current = Parameter(value: 0, digits: 0)
                    } else {
                        current.value = current.value * 10 + Int(byte - 0x30)
                        current.digits += 1
                    }
                }
                parameters.initializeElement(at: index, to: current)
                defer { _ = parameters.deinitialize() }
                reporting(UnsafeBufferPointer(parameters), report)
                return true
            }
        }
    }

    /// One decimal parameter: its value, and how many digits spelled it — `0`
    /// for an empty one.
    private struct Parameter {
        var value: Int
        var digits: Int

        /// The value as one component of a colour, or `nil` where the general
        /// reading's `UInt8(_:)` would refuse it: empty, or past 255.
        var component: UInt8? { digits > 0 ? UInt8(exactly: value) : nil }

        /// Whether this is the single digit `digit`, as text.
        func isDigit(_ digit: Int) -> Bool { digits == 1 && value == digit }
    }

    private static func reporting(_ parameters: UnsafeBufferPointer<Parameter>, _ report: (ColorSlot, Color?) -> Void) {
        var index = 0
        while index < parameters.count {
            let parameter = parameters[index].value
            switch parameter {
            case 0:
                report(.reset, nil)
            case 38, 48:
                let slot: ColorSlot = parameter == 38 ? .foreground : .background
                if index + 2 < parameters.count, parameters[index + 1].isDigit(5),
                    let value = parameters[index + 2].component
                {
                    report(slot, Color.palette256(value))
                    index += 3
                    continue
                }
                if index + 4 < parameters.count, parameters[index + 1].isDigit(2),
                    let red = parameters[index + 2].component,
                    let green = parameters[index + 3].component,
                    let blue = parameters[index + 4].component
                {
                    // swiftlint:disable:next framework_colour_literal - a colour read back out of an escape, not ink
                    report(slot, Color.rgb(red, green, blue))
                    index += 5
                    continue
                }
            case 30...37, 90...97, 40...47, 100...107:
                let isBackground = (40...47).contains(parameter) || (100...107).contains(parameter)
                let isBright = parameter >= 90
                let base = parameter - (isBright ? (isBackground ? 100 : 90) : (isBackground ? 40 : 30))
                if let color = basicColor(base: base, isBright: isBright) {
                    report(isBackground ? .background : .foreground, color)
                }
            case 39:
                report(.foreground, nil)
            case 49:
                report(.background, nil)
            default:
                break
            }
            index += 1
        }
    }
}
