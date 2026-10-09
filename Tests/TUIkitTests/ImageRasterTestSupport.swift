//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRasterTestSupport.swift
//
//  Reading back what a raster `Image` holds: its picture is a value the bitmap
//  path made (`_SourcedImageRaster`), which `Image` keeps as an existential.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit
@testable import TUIkitBitmaps
@testable import TUIkitFoundation

extension Image {
    /// The picture this image holds, as the bitmap path made it from a source
    /// — or `nil` for a symbol, or a picture of another kind.
    var sourcedRaster: _SourcedImageRaster? {
        guard case .raster(let raster) = content else { return nil }
        return raster as? _SourcedImageRaster
    }

    /// The pixels that picture carries already decoded, if any.
    var decoded: _DecodedImage? {
        sourcedRaster?.decoded
    }
}
