//  🖥️ TUI — A Terminal UI framework for Swift
//  FrostResolutionDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// The same glass over the same photograph four times, its frost drawn at the
/// terminal's pixels downsampled by 8, 4, 2 and not at all
/// (``MaterialFrostResolution``): where a picture the terminal draws is
/// behind a material, the frost is a picture of its own, and this is how many
/// pixels a cell it has — smoother the more it has, and the more it sends.
struct FrostResolutionDemo: View {
    /// The terminal's cell, in its own pixels: what the labels count from.
    @Environment(\.imageCellPixels) private var cell

    private static let factors = [8, 4, 2, 1]

    /// The photograph's box, and the glass panel's over its middle: wide
    /// enough to frost most of the picture, short enough to leave it bare above
    /// and below, to compare.
    private static let photo = (width: 32, height: 11)
    private static let panel = (width: 26, height: 5)

    var body: some View {
        DemoSection("page.colors.section.frostResolution") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.colors.frostResolution.caption")
                    .foregroundStyle(.palette.foregroundSecondary)
                // Two by two, so the four sit close enough to compare on a
                // terminal of ordinary width.
                ForEach([Array(Self.factors.prefix(2)), Array(Self.factors.suffix(2))], id: \.self) { pair in
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(pair, id: \.self) { factor in
                            pane(
                                factor == 1 ? ".native" : ".downsampled(by: \(factor))", grid: grid(factor),
                                resolution: .downsampled(by: factor))
                        }
                    }
                }
            }
        }
    }

    /// The photograph with a glass panel over its middle, frosted at `resolution`,
    /// and what that costs a cell below it.
    private func pane(_ name: String, grid: String, resolution: MaterialFrostResolution) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                photo
                Text(verbatim: name)
                    .frame(width: Self.panel.width, height: Self.panel.height)
                    .background(.thinMaterial)
            }
            .materialFrostResolution(resolution)
            Text(verbatim: grid).foregroundStyle(.palette.foregroundSecondary)
        }
    }

    /// What `factor` makes of this terminal's cell: its pixels, and their bytes.
    private func grid(_ factor: Int) -> String {
        let across = max(1, (cell.width + factor / 2) / factor)
        let down = max(1, (cell.height + factor / 2) / factor)
        return "\(across)×\(down) · \(across * down * 4) B"
    }

    @ViewBuilder private var photo: some View {
        if let path = Bundle.module.path(forResource: "demo-image", ofType: "jpg", inDirectory: "Resources") {
            Image(.file(path))
                .resizable()
                .scaledToFit()
                .frame(width: Self.photo.width, height: Self.photo.height)
        } else {
            Text("\(L("page.imageFile.resourceNotFound")): demo-image.jpg")
                .foregroundStyle(.error)
        }
    }
}
