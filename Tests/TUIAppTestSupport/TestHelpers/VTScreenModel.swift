//  🖥️ TUI — A Terminal UI framework for Swift
//  VTScreenModel.swift
//
//  A small terminal, for asking what a stream of writes leaves on the screen:
//  moves, styling, erases with the pen's background, regions, margins and the
//  ways of scrolling them. What `scroll_region_probe.py` measured the hosts to do.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUICore
@testable import TUIFoundation

/// A grid of one-scalar cells, and the pen they were drawn with.
struct VTScreenModel {
    struct Cell: Equatable {
        var scalar: Unicode.Scalar = " "
        var style = SGRState()

        /// Whether the two show the same thing. A blank cell's foreground is
        /// nobody's business, as the writer's diff says.
        func paintsLike(_ other: Self) -> Bool {
            guard scalar == other.scalar else { return false }
            return scalar == " " ? style.paintsBlankCellsIdentically(to: other.style) : style == other.style
        }
    }

    let width: Int
    let height: Int
    private(set) var cells: [[Cell]]
    private(set) var row = 0
    private(set) var column = 0
    private(set) var pen = SGRState()
    private(set) var top = 0
    private(set) var bottom: Int
    private(set) var left = 0
    private(set) var right: Int
    private(set) var marginMode = false
    /// How many times `CSI S` or `CSI T` came through.
    private(set) var scrolls = 0
    private var saved = (row: 0, column: 0)

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bottom = height - 1
        right = width - 1
        cells = Array(repeating: Array(repeating: Cell(), count: width), count: height)
    }

    /// Whether nothing a frame set is still in force.
    var regionIsReset: Bool {
        top == 0 && bottom == height - 1 && left == 0 && right == width - 1 && !marginMode
    }

    mutating func feed(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                index = escape(scalars, at: index)
            } else {
                index += 1
                if scalar.value >= 0x20 { put(scalar) }
            }
        }
    }

    private mutating func put(_ scalar: Unicode.Scalar) {
        guard row < height, column < width else { return }
        cells[row][column] = Cell(scalar: scalar, style: pen)
        column = min(width - 1, column + 1)
    }

    private mutating func escape(_ scalars: [Unicode.Scalar], at start: Int) -> Int {
        guard start + 1 < scalars.count else { return scalars.count }
        let next = scalars[start + 1]
        switch next.value {
        case 0x37:  // ESC 7
            saved = (row, column)
            return start + 2
        case 0x38:  // ESC 8
            (row, column) = saved
            return start + 2
        case 0x5B:  // CSI
            var end = start + 2
            while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
            guard end < scalars.count else { return scalars.count }
            var parameters = ""
            for scalar in scalars[(start + 2)..<end] { parameters.unicodeScalars.append(scalar) }
            csi(parameters, final: Character(scalars[end]))
            return end + 1
        default:
            return start + 2
        }
    }

    private mutating func csi(_ parameters: String, final: Character) {
        if final == "m" {
            pen.apply("\u{1B}[\(parameters)m")
            return
        }
        if parameters.hasPrefix("?") {
            if parameters == "?69" {
                marginMode = final == "h"
                if !marginMode { (left, right) = (0, width - 1) }
            }
            return
        }
        let numbers = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func value(_ index: Int, _ fallback: Int) -> Int {
            guard index < numbers.count, let number = numbers[index], number > 0 else { return fallback }
            return number
        }
        switch final {
        case "H":
            row = min(height - 1, value(0, 1) - 1)
            column = min(width - 1, value(1, 1) - 1)
        case "K":
            erase(mode: value(0, 0))
        case "r":
            top = value(0, 1) - 1
            bottom = value(1, height) - 1
            (row, column) = (0, 0)
        case "s":
            setMargins(left: value(0, 1) - 1, right: value(1, width) - 1)
        case "S":
            scroll(by: value(0, 1))
        case "T":
            scroll(by: -value(0, 1))
        default:
            break
        }
    }

    private mutating func erase(mode: Int) {
        let (from, to): (Int, Int) =
            switch mode {
            case 2: (0, width)
            case 1: (0, column + 1)
            default: (column, width)
            }
        for erased in from..<to { cells[row][erased] = Cell(style: pen) }
    }

    /// DECSLRM in margin mode, and a cursor save without it: `CSI s` is both.
    private mutating func setMargins(left newLeft: Int, right newRight: Int) {
        guard marginMode else {
            saved = (row, column)
            return
        }
        (left, right) = (newLeft, newRight)
        (row, column) = (0, 0)
    }

    private mutating func scroll(by distance: Int) {
        scrolls += 1
        let order = distance > 0 ? Array(top...bottom) : Array((top...bottom).reversed())
        for target in order {
            let source = target + distance
            for cell in left...right {
                cells[target][cell] = (top...bottom).contains(source) ? cells[source][cell] : Cell(style: pen)
            }
        }
    }

    /// Where the two screens first paint differently, or `nil`.
    func firstDifference(from other: Self) -> String? {
        for y in 0..<height {
            for x in 0..<width where !cells[y][x].paintsLike(other.cells[y][x]) {
                let mine = cells[y][x]
                let theirs = other.cells[y][x]
                return "(\(y),\(x)): \(mine.scalar) \(mine.style) against \(theirs.scalar) \(theirs.style)"
            }
        }
        return nil
    }
}

#endif
