import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
@testable import SceneRuntime
import XCTest

final class SceneImageAlphaMaskSamplerTests: XCTestCase {
    func testPrewarmMakesFirstGestureSamplingDecodeFreeAndPurgeDropsThePlane() throws {
        let fixture = try makeMaskFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sampler = SceneImageAlphaMaskSampler(minimumOpaqueCoverage: 128)

        try sampler.prewarm(fixture.asset)
        XCTAssertEqual(sampler.decodeCountForTesting(fixture.asset), 1)

        _ = try sampler.isOpaque(
            in: fixture.asset,
            at: .init(x: 0.25, y: 0.25)
        )
        XCTAssertEqual(sampler.decodeCountForTesting(fixture.asset), 1)

        sampler.purge()
        XCTAssertEqual(sampler.decodeCountForTesting(fixture.asset), 0)
        _ = try sampler.isOpaque(
            in: fixture.asset,
            at: .init(x: 0.75, y: 0.75)
        )
        XCTAssertEqual(sampler.decodeCountForTesting(fixture.asset), 1)
    }

    func testSamplerUsesTopLeftCoordinatesAndAuthoredCoverageThreshold() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "alpha-mask-sampler-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let data = try grayscalePNG(
            width: 2,
            height: 2,
            pixels: [
                255, 0,
                64, 200,
            ]
        )
        try data.write(to: root.appending(path: "mask.png"))
        let asset = SceneResolvedAsset(
            packagePath: "mask.png",
            activatedPackageRoot: root,
            byteCount: Int64(data.count),
            sha256: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
        let sampler = SceneImageAlphaMaskSampler(minimumOpaqueCoverage: 128)

        XCTAssertTrue(try sampler.isOpaque(
            in: asset,
            at: .init(x: 0.1, y: 0.1)
        ))
        XCTAssertFalse(try sampler.isOpaque(
            in: asset,
            at: .init(x: 0.9, y: 0.1)
        ))
        XCTAssertFalse(try sampler.isOpaque(
            in: asset,
            at: .init(x: 0.1, y: 0.9)
        ))
        XCTAssertTrue(try sampler.isOpaque(
            in: asset,
            at: .init(x: 0.9, y: 0.9)
        ))
        XCTAssertThrowsError(
            try sampler.isOpaque(in: asset, at: .init(x: -0.1, y: 0.5))
        ) { error in
            XCTAssertEqual(
                error as? SceneImageAlphaMaskSamplerError,
                .invalidUnitPoint
            )
        }
    }

    func testCoverageDecodePreservesTopLeftPixelOrder() throws {
        let data = try grayscalePNG(
            width: 2,
            height: 2,
            pixels: [
                255, 0,
                64, 200,
            ]
        )

        let decoded = try SceneImageAlphaMaskSampler.decodeCoverageBytes(data)

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.bytes, [255, 0, 64, 200])
    }

    func testCoverageDecodeRejectsNonImageBytes() {
        XCTAssertThrowsError(
            try SceneImageAlphaMaskSampler.decodeCoverageBytes(Data("not-an-image".utf8))
        ) { error in
            XCTAssertEqual(
                error as? SceneImageAlphaMaskSamplerError,
                .undecodableImage
            )
        }
    }

    private func grayscalePNG(
        width: Int,
        height: Int,
        pixels: [UInt8]
    ) throws -> Data {
        XCTAssertEqual(pixels.count, width * height)
        let provider = try XCTUnwrap(
            CGDataProvider(data: Data(pixels) as CFData)
        )
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output,
                "public.png" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func makeMaskFixture() throws -> (
        root: URL,
        asset: SceneResolvedAsset
    ) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "alpha-mask-prewarm-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let data = try grayscalePNG(
            width: 2,
            height: 2,
            pixels: [255, 0, 64, 200]
        )
        try data.write(to: root.appending(path: "mask.png"))
        return (
            root,
            SceneResolvedAsset(
                packagePath: "mask.png",
                activatedPackageRoot: root,
                byteCount: Int64(data.count),
                sha256: SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        )
    }
}
