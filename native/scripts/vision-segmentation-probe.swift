import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Vision

enum ProbeError: Error, CustomStringConvertible {
    case usage
    case imageLoad
    case noForeground
    case noPerson

    var description: String {
        switch self {
        case .usage: return "usage: vision-segmentation-probe.swift INPUT.png OUTPUT_DIRECTORY"
        case .imageLoad: return "could not decode input image"
        case .noForeground: return "Vision returned no foreground-instance observation"
        case .noPerson: return "Vision returned no person-segmentation observation"
        }
    }
}

func writeMask(_ pixelBuffer: CVPixelBuffer, to url: URL, width: Int, height: Int) throws {
    let source = CIImage(cvPixelBuffer: pixelBuffer)
    let scaleX = CGFloat(width) / source.extent.width
    let scaleY = CGFloat(height) / source.extent.height
    let image = source
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])
    try context.writePNGRepresentation(
        of: image,
        to: url,
        format: .L8,
        colorSpace: CGColorSpaceCreateDeviceGray()
    )
}

func main() throws {
    guard CommandLine.arguments.count == 3 else { throw ProbeError.usage }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ProbeError.imageLoad
    }

    let foregroundHandler = VNImageRequestHandler(cgImage: image, options: [:])
    let foregroundRequest = VNGenerateForegroundInstanceMaskRequest()
    try foregroundHandler.perform([foregroundRequest])
    guard let foreground = foregroundRequest.results?.first else { throw ProbeError.noForeground }
    let instanceIDs = foreground.allInstances.sorted()
    for instanceID in instanceIDs {
        let mask = try foreground.generateScaledMaskForImage(
            forInstances: IndexSet(integer: instanceID),
            from: foregroundHandler
        )
        try writeMask(
            mask,
            to: outputURL.appendingPathComponent(String(format: "foreground-instance-%02d.png", instanceID)),
            width: image.width,
            height: image.height
        )
    }
    if !instanceIDs.isEmpty {
        let combined = try foreground.generateScaledMaskForImage(
            forInstances: foreground.allInstances,
            from: foregroundHandler
        )
        try writeMask(
            combined,
            to: outputURL.appendingPathComponent("foreground-all.png"),
            width: image.width,
            height: image.height
        )
    }

    let personHandler = VNImageRequestHandler(cgImage: image, options: [:])
    let personRequest = VNGeneratePersonSegmentationRequest()
    personRequest.qualityLevel = .accurate
    personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try personHandler.perform([personRequest])
    guard let person = personRequest.results?.first else { throw ProbeError.noPerson }
    try writeMask(
        person.pixelBuffer,
        to: outputURL.appendingPathComponent("people-all.png"),
        width: image.width,
        height: image.height
    )

    print("foreground instances: \(instanceIDs.map(String.init).joined(separator: ","))")
    print("canvas: \(image.width)x\(image.height)")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
