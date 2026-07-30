import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoadError: LocalizedError {
    case unreadable
    case undecodable

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Could not read file"
        case .undecodable: return "Could not decode image"
        }
    }
}

public enum ImageWriteError: LocalizedError {
    case destinationUnavailable
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .destinationUnavailable: return "Could not create output file"
        case .encodingFailed: return "Could not encode image"
        }
    }
}

public enum ImageIOSupport {
    /// Decode a file, baking in its EXIF orientation.
    ///
    /// `CGImageSourceCreateImageAtIndex` hands back raw sensor-order pixels, so
    /// a portrait frame from a camera arrives rotated unless the orientation tag
    /// is applied here.
    public static func load(url: URL,
                     raw settings: RawDevelopSettings = RawDevelopSettings(),
                     maxDimension: Int? = nil) throws -> CGImage {
        if let raw = loadRAW(url: url, settings: settings, maxDimension: maxDimension) {
            return raw
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoadError.unreadable
        }
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, opts as CFDictionary) else {
            throw ImageLoadError.undecodable
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return applyOrientation(exif, to: image)
    }

    /// Develop a camera RAW file with every "pleasing picture" adjustment
    /// disabled. See `RawDevelopSettings` for why the defaults are what they are.
    ///
    /// Returns nil for anything that is not a RAW file.
    ///
    /// `maxDimension` is passed to the decoder rather than applied afterwards, so
    /// re-developing for the preview when a setting changes does not have to
    /// demosaic the full sensor every time.
    static func loadRAW(url: URL,
                        settings: RawDevelopSettings = RawDevelopSettings(),
                        maxDimension: Int? = nil) -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }

        if settings.useNeutralBalance {
            filter.neutralChromaticity = CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0)
        } else {
            filter.neutralTemperature = settings.temperature
            filter.neutralTint = settings.tint
        }
        filter.exposure = settings.exposure
        if let maxDimension {
            let native = max(filter.nativeSize.width, filter.nativeSize.height)
            if native > 0, CGFloat(maxDimension) < native {
                filter.scaleFactor = Float(CGFloat(maxDimension) / native)
            }
        }
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.contrastAmount = 0
        filter.detailAmount = 0
        filter.sharpnessAmount = 0
        filter.colorNoiseReductionAmount = 0
        filter.luminanceNoiseReductionAmount = 0
        filter.isGamutMappingEnabled = false

        guard let output = filter.outputImage,
              let cs = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // Rendered at RGBA16, not the default RGBA8. Developing a raw file to 8
        // bits and then widening it later is the trap this path exists to avoid:
        // measured on the sample frame, an 8-bit development left the infrared
        // output with 101 distinct levels across 1.5 megapixels.
        // CIRAWFilter already applies the orientation tag.
        return CIContext(options: [.workingColorSpace: cs])
            .createCGImage(output, from: output.extent, format: .RGBA16, colorSpace: cs)
    }

    private static func applyOrientation(_ exif: UInt32, to image: CGImage) -> CGImage {
        guard exif > 1, exif <= 8 else { return image }
        let ci = CIImage(cgImage: image).oriented(forExifOrientation: Int32(exif))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let ctx = CIContext(options: [.workingColorSpace: cs])
        // Keep 16 bits through the rotation, so a portrait frame is not quietly
        // reduced to 8 while a landscape one is not.
        return ctx.createCGImage(ci, from: ci.extent, format: .RGBA16, colorSpace: cs) ?? image
    }

    /// Scale the image down so the interactive preview stays cheap.
    ///
    /// Via CoreImage rather than a `CGContext`: an 8-bit context here would undo
    /// the 16-bit decode, and a 16-bit one cannot be drawn into on this platform —
    /// `CGContext.draw` into 16 bits per component silently produces all zeros,
    /// which is why the decode path uses `CIContext.render` too.
    public static func downsample(image: CGImage, maxDimension: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(longest)

        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        guard let scaled = CIFilter(name: "CILanczosScaleTransform", parameters: [
            kCIInputImageKey: CIImage(cgImage: image),
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])?.outputImage else { return image }

        let ctx = CIContext(options: [.workingColorSpace: cs])
        return ctx.createCGImage(scaled, from: scaled.extent,
                                 format: .RGBA16, colorSpace: cs) ?? image
    }

    /// What a finished conversion can be written as.
    ///
    /// Both are fed the **16-bit** render rather than the 8-bit preview one, which is
    /// not cosmetic: measured over a 16384-step ramp, a 16-bit source through HEIC
    /// yields 924 distinct levels against 256 from an 8-bit source. Pre-quantizing to
    /// 8 bits first would throw that away.
    public enum ExportFormat: String, CaseIterable, Codable, Sendable {
        /// For finished pictures. 10 bits per channel, lossy, small.
        case heic
        /// For handing to another editor. 16 bits per channel, lossless, large.
        ///
        /// TIFF has no 10-bit mode — the format stores 8 or 16 bits per channel — so
        /// this is 16-bit, which carries the whole render exactly and is a superset
        /// of what HEIC's 10 bits could hold. Lightroom reads it natively.
        case tiff

        public var utType: UTType {
            switch self {
            case .heic: return .heic
            case .tiff: return .tiff
            }
        }

        public var fileExtension: String {
            switch self {
            case .heic: return "heic"
            case .tiff: return "tif"
            }
        }

        public var label: String {
            switch self {
            case .heic: return "HEIC"
            case .tiff: return "16-bit TIFF"
            }
        }
    }

    /// HEIC is the only choice offered in the save panel.
    public static let exportTypes: [UTType] = [.heic]
    public static let exportExtension = ExportFormat.heic.fileExtension

    /// Quality 1.0 is not better here — measured, it produces *fewer* distinct
    /// levels than 0.95 while more than doubling the file size.
    private static let quality = 0.95

    /// Write a 16-bit render.
    ///
    /// Goes through `CGImageDestination` rather than `NSImage`, so the sRGB profile
    /// survives instead of being round-tripped.
    public static func write(_ image: RenderedImage16, to url: URL,
                             format: ExportFormat = .heic) throws {
        guard let cg = makeCGImage16(image) else { throw ImageWriteError.encodingFailed }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil
        ) else { throw ImageWriteError.destinationUnavailable }

        let options: [CFString: Any]
        switch format {
        case .heic:
            options = [kCGImageDestinationLossyCompressionQuality: quality]
        case .tiff:
            // Uncompressed, which is measured rather than lazy. On the 5184×3888
            // sample frame, every option is lossless and comes back bit-exact, so
            // the only question is size and time:
            //
            // | compression | size | vs raw | write |
            // |---|---|---|---|
            // | **none** | **120 MB** | **100%** | **106 ms** |
            // | LZW (5) | 155 MB | 128% | 816 ms |
            // | deflate (8) | 116 MB | 95% | 2218 ms |
            // | PackBits (32773) | 121 MB | 100% | 255 ms |
            //
            // LZW *expands* 16-bit photographic data — it is built for runs of
            // repeated bytes and there are none in noisy low-order bits. Deflate
            // saves 4% for twenty times the write cost. Uncompressed is also the
            // most widely readable, which matters for a hand-off file.
            options = [:]
        }

        CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageWriteError.encodingFailed }
    }

    /// Build a 16-bit `CGImage` straight from the sample buffer.
    ///
    /// Constructed from a data provider rather than by drawing into a 16-bit
    /// `CGContext` — drawing into one silently yields all zeros on this platform.
    private static func makeCGImage16(_ image: RenderedImage16) -> CGImage? {
        let byteCount = image.width * image.height * 3 * 2
        var pixels = image.pixels
        guard let data = pixels.withUnsafeMutableBytes({ raw -> CFData? in
            guard let base = raw.baseAddress else { return nil }
            return CFDataCreate(nil, base.assumingMemoryBound(to: UInt8.self), byteCount)
        }), let provider = CGDataProvider(data: data),
              let cs = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        return CGImage(
            width: image.width, height: image.height,
            bitsPerComponent: 16, bitsPerPixel: 48,
            bytesPerRow: image.width * 6,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                .union(.byteOrder16Little),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

extension ImageIOSupport {
    /// Whether this file will go down the RAW development path, so the UI knows
    /// whether to offer the balance and headroom controls.
    public static func isRAW(url: URL) -> Bool {
        CIRAWFilter(imageURL: url) != nil
    }
}

extension ImageIOSupport {
    /// Pixel dimensions read from the file's metadata, without decoding it.
    public static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        if let filter = CIRAWFilter(imageURL: url) {
            let size = filter.nativeSize
            if size.width > 0, size.height > 0 {
                return (Int(size.width), Int(size.height))
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // A quarter-turn in the orientation tag swaps the stored dimensions.
        let exif = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(exif) ? (h, w) : (w, h)
    }
}
