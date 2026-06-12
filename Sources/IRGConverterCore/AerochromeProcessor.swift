import Accelerate
import CoreGraphics
import Foundation

public struct AerochromeParams {
    public var fracRx: Float = 0.8
    public var fracRy: Float = 0.2
    public var fracGx: Float = 0.7
    public var fracGy: Float = 0.3
    public var fracBx: Float = 0.0
    public var fracBy: Float = 1.0

    public var gammaRx: Float = 2.2
    public var gammaRy: Float = 1.4
    public var gammaGx: Float = 2.0
    public var gammaGy: Float = 1.5
    public var gammaBx: Float = 2.2
    public var gammaBy: Float = 1.2

    public var subtractIRRed: Float = 0.5
    public var subtractIRGreen: Float = 0.8

    public var overallGamma: Float = 1.6

    public var outputMapR: Int = 2
    public var outputMapG: Int = 0
    public var outputMapB: Int = 1

    public init() {}
}

public class AerochromeProcessor {
    public init() {}

    private var n = 0
    private var width = 0
    private var height = 0

    // Cached input (never changes after prepare)
    private var irF: [Float] = []
    private var x1F: [Float] = []
    private var x2F: [Float] = []
    private var omx1: [Float] = []
    private var omx2: [Float] = []
    private var omy: [Float] = []
    private var ones: [Float] = []

    // Pre-allocated working buffers
    private var powRx: [Float] = []
    private var powGx: [Float] = []
    private var powRy: [Float] = []
    private var powGy: [Float] = []
    private var powBy: [Float] = []
    private var gRxA: [Float] = []
    private var gGxA: [Float] = []
    private var gRyA: [Float] = []
    private var gGyA: [Float] = []
    private var gByA: [Float] = []
    private var z0: [Float] = []
    private var z1: [Float] = []
    private var z2: [Float] = []
    private var sr: [Float] = []
    private var sg: [Float] = []
    private var sb: [Float] = []
    private var tmp: [Float] = []
    private var tmp2: [Float] = []
    private var finalR: [Float] = []
    private var finalG: [Float] = []
    private var finalB: [Float] = []
    private var outR: [UInt8] = []
    private var outG: [UInt8] = []
    private var outB: [UInt8] = []

    public func prepare(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        n = width * height
        guard n > 0 else { return }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let srcData = ctx.data else { return }
        let src = srcData.assumingMemoryBound(to: UInt8.self)

        var bArr = [UInt8](repeating: 0, count: n)
        var gArr = [UInt8](repeating: 0, count: n)
        var rArr = [UInt8](repeating: 0, count: n)

        let srcStride = ctx.bytesPerRow
        for y in 0..<height {
            let ro = y * srcStride
            let io = y * width
            for x in 0..<width {
                let p = ro + x * 4
                let i = io + x
                bArr[i] = src[p]
                gArr[i] = src[p + 1]
                rArr[i] = src[p + 2]
            }
        }

        let nLen = vDSP_Length(n)
        irF = [Float](repeating: 0, count: n)
        x1F = [Float](repeating: 0, count: n)
        x2F = [Float](repeating: 0, count: n)
        vDSP_vfltu8(rArr, 1, &irF, 1, nLen)
        vDSP_vfltu8(gArr, 1, &x1F, 1, nLen)
        vDSP_vfltu8(bArr, 1, &x2F, 1, nLen)
        let s: Float = 1.0 / 255.0
        vDSP_vsmul(irF, 1, [s], &irF, 1, nLen)
        vDSP_vsmul(x1F, 1, [s], &x1F, 1, nLen)
        vDSP_vsmul(x2F, 1, [s], &x2F, 1, nLen)

        // Pre-compute invariant 1-x arrays
        ones = [Float](repeating: 1, count: n)
        omx1 = [Float](repeating: 0, count: n)
        omx2 = [Float](repeating: 0, count: n)
        omy = [Float](repeating: 0, count: n)
        vDSP_vsub(x1F, 1, ones, 1, &omx1, 1, nLen)
        vDSP_vsub(x2F, 1, ones, 1, &omx2, 1, nLen)
        vDSP_vsub(irF, 1, ones, 1, &omy, 1, nLen)

        // Pre-allocate all working buffers
        let cap = n
        powRx = [Float](repeating: 0, count: cap)
        powGx = [Float](repeating: 0, count: cap)
        powRy = [Float](repeating: 0, count: cap)
        powGy = [Float](repeating: 0, count: cap)
        powBy = [Float](repeating: 0, count: cap)
        gRxA = [Float](repeating: 0, count: cap)
        gGxA = [Float](repeating: 0, count: cap)
        gRyA = [Float](repeating: 0, count: cap)
        gGyA = [Float](repeating: 0, count: cap)
        gByA = [Float](repeating: 0, count: cap)
        z0 = [Float](repeating: 0, count: cap)
        z1 = [Float](repeating: 0, count: cap)
        z2 = [Float](repeating: 0, count: cap)
        sr = [Float](repeating: 0, count: cap)
        sg = [Float](repeating: 0, count: cap)
        sb = [Float](repeating: 0, count: cap)
        tmp = [Float](repeating: 0, count: cap)
        tmp2 = [Float](repeating: 0, count: cap)
        finalR = [Float](repeating: 0, count: cap)
        finalG = [Float](repeating: 0, count: cap)
        finalB = [Float](repeating: 0, count: cap)
        outR = [UInt8](repeating: 0, count: cap)
        outG = [UInt8](repeating: 0, count: cap)
        outB = [UInt8](repeating: 0, count: cap)
    }

    public func process(params: AerochromeParams) -> CGImage? {
        guard n > 0 else { return nil }
        let nLen = vDSP_Length(n)
        let p = params

        // Pre-store scalars in local vars (avoids [value] array creation in vDSP calls)
        var frRx = p.fracRx, frRy = p.fracRy
        var frGx = p.fracGx, frGy = p.fracGy
        var frBy = p.fracBy
        var subRf = p.subtractIRRed, subGf = p.subtractIRGreen
        var og: Float = 1.0 / p.overallGamma
        let mapR = p.outputMapR, mapG = p.outputMapG, mapB = p.outputMapB

        // Step 1: Fill gamma arrays with current values
        var gv: Float = p.gammaRx
        vDSP_vfill(&gv, &gRxA, 1, nLen)
        gv = p.gammaGx
        vDSP_vfill(&gv, &gGxA, 1, nLen)
        gv = p.gammaRy
        vDSP_vfill(&gv, &gRyA, 1, nLen)
        gv = p.gammaGy
        vDSP_vfill(&gv, &gGyA, 1, nLen)
        gv = p.gammaBy
        vDSP_vfill(&gv, &gByA, 1, nLen)

        // Step 2: vvpowf: result = base ^ exponent
        var count32 = Int32(n)
        vvpowf(&powRx, &omx1, &gRxA, &count32)
        vvpowf(&powGx, &omx2, &gGxA, &count32)
        vvpowf(&powRy, &omy, &gRyA, &count32)
        vvpowf(&powGy, &omy, &gGyA, &count32)
        vvpowf(&powBy, &omy, &gByA, &count32)

        // Step 3: z0 = (1-powRx)*frRx + (1-powRy)*frRy
        vDSP_vsub(powRx, 1, ones, 1, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &frRx, &z0, 1, nLen)
        vDSP_vsub(powRy, 1, ones, 1, &tmp2, 1, nLen)
        vDSP_vsmul(tmp2, 1, &frRy, &tmp2, 1, nLen)
        vDSP_vadd(z0, 1, tmp2, 1, &z0, 1, nLen)

        // Step 4: z1 = (1-powGx)*frGx + (1-powGy)*frGy
        vDSP_vsub(powGx, 1, ones, 1, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &frGx, &z1, 1, nLen)
        vDSP_vsub(powGy, 1, ones, 1, &tmp2, 1, nLen)
        vDSP_vsmul(tmp2, 1, &frGy, &tmp2, 1, nLen)
        vDSP_vadd(z1, 1, tmp2, 1, &z1, 1, nLen)

        // Step 5: z2 = (1-powBy)*frBy
        vDSP_vsub(powBy, 1, ones, 1, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &frBy, &z2, 1, nLen)

        // Step 6: sr = max(z0 - z2*subRf, 0), sg = max(z1 - z2*subGf, 0), sb = max(z2, 0)
        vDSP_vsmul(z2, 1, &subRf, &tmp, 1, nLen)
        vDSP_vsub(z0, 1, tmp, 1, &sr, 1, nLen)
        var zero: Float = 0
        vDSP_vmax(sr, 1, &zero, 0, &sr, 1, nLen)

        vDSP_vsmul(z2, 1, &subGf, &tmp, 1, nLen)
        vDSP_vsub(z1, 1, tmp, 1, &sg, 1, nLen)
        vDSP_vmax(sg, 1, &zero, 0, &sg, 1, nLen)

        vDSP_vmax(z2, 1, &zero, 0, &sb, 1, nLen)

        // Step 7: Channel mapping + final gamma
        vDSP_vfill(&og, &tmp, 1, nLen)

        switch mapR {
        case 0: vvpowf(&finalR, &sr, &tmp, &count32)
        case 1: vvpowf(&finalR, &sg, &tmp, &count32)
        default: vvpowf(&finalR, &sb, &tmp, &count32)
        }
        switch mapG {
        case 0: vvpowf(&finalG, &sr, &tmp, &count32)
        case 1: vvpowf(&finalG, &sg, &tmp, &count32)
        default: vvpowf(&finalG, &sb, &tmp, &count32)
        }
        switch mapB {
        case 0: vvpowf(&finalB, &sr, &tmp, &count32)
        case 1: vvpowf(&finalB, &sg, &tmp, &count32)
        default: vvpowf(&finalB, &sb, &tmp, &count32)
        }

        // Step 8: Clamp [0,1], scale to [0,255], convert to UInt8
        var one: Float = 1
        vDSP_vclip(finalR, 1, &zero, &one, &finalR, 1, nLen)
        vDSP_vclip(finalG, 1, &zero, &one, &finalG, 1, nLen)
        vDSP_vclip(finalB, 1, &zero, &one, &finalB, 1, nLen)

        var scale255: Float = 255
        vDSP_vsmul(finalR, 1, &scale255, &finalR, 1, nLen)
        vDSP_vsmul(finalG, 1, &scale255, &finalG, 1, nLen)
        vDSP_vsmul(finalB, 1, &scale255, &finalB, 1, nLen)

        vDSP_vfixru8(finalR, 1, &outR, 1, nLen)
        vDSP_vfixru8(finalG, 1, &outG, 1, nLen)
        vDSP_vfixru8(finalB, 1, &outB, 1, nLen)

        // Step 9: Write to CGContext
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)

        guard let dstCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        guard let dstData = dstCtx.data else { return nil }
        let dst = dstData.assumingMemoryBound(to: UInt8.self)
        let dstStride = dstCtx.bytesPerRow

        for y in 0..<height {
            let ro = y * dstStride
            let io = y * width
            for x in 0..<width {
                let p = ro + x * 4
                let i = io + x
                dst[p] = outB[i]
                dst[p + 1] = outG[i]
                dst[p + 2] = outR[i]
            }
        }

        return dstCtx.makeImage()
    }

    public func process(cgImage: CGImage, params: AerochromeParams) -> CGImage? {
        prepare(cgImage: cgImage)
        return process(params: params)
    }
}
