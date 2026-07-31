import ContentKit
import CoreGraphics
import Foundation
import ImageIO

public enum SceneImageAlphaMaskSamplerError: Error, Equatable, Sendable {
    case invalidUnitPoint
    case undecodableImage
    case invalidDimensions(width: Int, height: Int)
    case pixelBudgetExceeded(actual: Int, maximum: Int)
    case rasterizationFailed
}

/// Decodes an authored alpha mask into one immutable top-left-origin coverage
/// plane. The source bytes cross `SceneAssetDataLoader` first, so the first
/// use is still bound to the signed package digest. Package generations are
/// immutable; the cache is purged when the owning chapter session ends.
public final class SceneImageAlphaMaskSampler: @unchecked Sendable,
    SceneAlphaMaskSampling
{
    public static let maximumPixelCount = 16_777_216

    private struct CoveragePlane: Sendable {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private let minimumOpaqueCoverage: UInt8
    private let lock = NSLock()
    private var planesByDigest: [String: CoveragePlane] = [:]
    private var decodeCountByDigest: [String: Int] = [:]

    public init(minimumOpaqueCoverage: UInt8 = 128) {
        self.minimumOpaqueCoverage = minimumOpaqueCoverage
    }

    public func isOpaque(
        in alphaMask: SceneResolvedAsset,
        at unitPoint: NormalizedPoint
    ) throws -> Bool {
        try Task.checkCancellation()
        guard unitPoint.isUnitPoint else {
            throw SceneImageAlphaMaskSamplerError.invalidUnitPoint
        }
        let key = "\(alphaMask.sha256):\(alphaMask.byteCount)"
        let plane: CoveragePlane
        if let cached = locked({ planesByDigest[key] }) {
            plane = cached
        } else {
            let data = try SceneAssetDataLoader.load(alphaMask)
            try Task.checkCancellation()
            locked { decodeCountByDigest[key, default: 0] += 1 }
            let decoded = try Self.decodeCoveragePlane(data)
            try Task.checkCancellation()
            plane = locked {
                if let existing = planesByDigest[key] { return existing }
                planesByDigest[key] = decoded
                return decoded
            }
        }

        let x = min(Int((unitPoint.x * Double(plane.width)).rounded(.down)), plane.width - 1)
        let y = min(Int((unitPoint.y * Double(plane.height)).rounded(.down)), plane.height - 1)
        return plane.bytes[y * plane.width + x] >= minimumOpaqueCoverage
    }

    /// Loads, verifies and rasterises the selected mask without waiting for
    /// the user's first contact. The sampled value is irrelevant; successful
    /// return proves that subsequent gesture sampling uses the cached plane.
    public func prewarm(_ alphaMask: SceneResolvedAsset) throws {
        _ = try isOpaque(
            in: alphaMask,
            at: NormalizedPoint(x: 0.5, y: 0.5)
        )
    }

    public func purge() {
        locked {
            planesByDigest.removeAll(keepingCapacity: false)
            decodeCountByDigest.removeAll(keepingCapacity: false)
        }
    }

    func decodeCountForTesting(_ alphaMask: SceneResolvedAsset) -> Int {
        let key = "\(alphaMask.sha256):\(alphaMask.byteCount)"
        return locked { decodeCountByDigest[key, default: 0] }
    }

    static func decodeCoverageBytes(_ data: Data) throws -> (
        width: Int,
        height: Int,
        bytes: [UInt8]
    ) {
        let plane = try decodeCoveragePlane(data)
        return (plane.width, plane.height, plane.bytes)
    }

    private static func decodeCoveragePlane(_ data: Data) throws -> CoveragePlane {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw SceneImageAlphaMaskSamplerError.undecodableImage
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw SceneImageAlphaMaskSamplerError.invalidDimensions(
                width: width,
                height: height
            )
        }
        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow else {
            throw SceneImageAlphaMaskSamplerError.pixelBudgetExceeded(
                actual: .max,
                maximum: maximumPixelCount
            )
        }
        guard pixelCount.partialValue <= maximumPixelCount else {
            throw SceneImageAlphaMaskSamplerError.pixelBudgetExceeded(
                actual: pixelCount.partialValue,
                maximum: maximumPixelCount
            )
        }

        let rgbaByteCount = pixelCount.partialValue.multipliedReportingOverflow(by: 4)
        guard !rgbaByteCount.overflow else {
            throw SceneImageAlphaMaskSamplerError.pixelBudgetExceeded(
                actual: .max,
                maximum: maximumPixelCount
            )
        }
        var rgba = [UInt8](repeating: 0, count: rgbaByteCount.partialValue)
        let created = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            // Scene coordinates and mask sampling are top-left-origin. Core
            // Graphics images are bottom-left-origin without this transform.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setBlendMode(.normal)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else {
            throw SceneImageAlphaMaskSamplerError.rasterizationFailed
        }
        var coverage = [UInt8](repeating: 0, count: pixelCount.partialValue)
        for topY in 0 ..< height {
            if topY.isMultiple(of: 32) { try Task.checkCancellation() }
            let bitmapY = height - 1 - topY
            for x in 0 ..< width {
                let outputIndex = topY * width + x
                let rgbaIndex = (bitmapY * width + x) * 4
                // RGB is premultiplied by alpha, so transparent mask pixels
                // stay zero while white/gray coverage retains its intensity.
                coverage[outputIndex] = max(
                    rgba[rgbaIndex],
                    rgba[rgbaIndex + 1],
                    rgba[rgbaIndex + 2]
                )
            }
        }
        return CoveragePlane(width: width, height: height, bytes: coverage)
    }

    @discardableResult
    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
