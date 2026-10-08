//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RGBAImage+Orientation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage

extension RGBAImage {
    /// The image turned to `orientation`, as SwiftUI draws it (measured on
    /// macOS 15 with a numbered 2 × 3 image).
    package func oriented(_ orientation: Image.Orientation) -> RGBAImage {
        guard orientation != .up, width > 0, height > 0 else { return self }
        let turns: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: turns = true
        case .up, .upMirrored, .down, .downMirrored: turns = false
        }
        let columns = turns ? height : width
        let rows = turns ? width : height
        var out: [RGBA] = []
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let (x, y): (Int, Int)
                switch orientation {
                case .up: (x, y) = (column, row)
                case .upMirrored: (x, y) = (width - 1 - column, row)
                case .down: (x, y) = (width - 1 - column, height - 1 - row)
                case .downMirrored: (x, y) = (column, height - 1 - row)
                case .left: (x, y) = (width - 1 - row, column)
                case .leftMirrored: (x, y) = (row, column)
                case .right: (x, y) = (row, height - 1 - column)
                case .rightMirrored: (x, y) = (width - 1 - row, height - 1 - column)
                }
                out.append(pixels[y * width + x])
            }
        }
        return RGBAImage(width: columns, height: rows, pixels: out)
    }
}
