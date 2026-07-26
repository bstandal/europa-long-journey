import ContentKit
import Foundation

public enum BundledEssentialContentLoaderError: Error, Equatable, Sendable,
    CustomStringConvertible
{
    case resourceMissing(name: String, extension: String, subdirectory: String?)
    case resourceUnreadable
    case invalidPayload
    case packageIdentityMismatch(expected: PackageID, actual: PackageID)

    public var description: String {
        switch self {
        case let .resourceMissing(name, fileExtension, subdirectory):
            let location = subdirectory.map { " in \($0)" } ?? ""
            return "Bundled content resource \(name).\(fileExtension) is missing\(location)"
        case .resourceUnreadable:
            return "Bundled content bytes could not be read"
        case .invalidPayload:
            return "Bundled content is not a valid canonical package payload"
        case let .packageIdentityMismatch(expected, actual):
            return "Bundled package \(actual) cannot replace required package \(expected)"
        }
    }
}

/// Opens the code-signed essential payload through the same canonical decode
/// and repository boundary used after a downloaded package has been verified.
/// Missing or malformed launch content never becomes partially addressable.
public struct BundledEssentialContentLoader: Sendable {
    public let resourceName: String
    public let resourceExtension: String
    public let resourceSubdirectory: String?

    public init(
        resourceName: String = "essential-free-v1.content",
        resourceExtension: String = "json",
        resourceSubdirectory: String? = "JourneyContent"
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.resourceSubdirectory = resourceSubdirectory
    }

    public func load(from bundle: Bundle) throws -> ContentRepository {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceSubdirectory
        ) else {
            throw BundledEssentialContentLoaderError.resourceMissing(
                name: resourceName,
                extension: resourceExtension,
                subdirectory: resourceSubdirectory
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BundledEssentialContentLoaderError.resourceUnreadable
        }
        return try load(data: data)
    }

    public func load(data: Data) throws -> ContentRepository {
        let payload = try decodePayload(data: data)
        return try ContentRepository(
            bundledEssentialPayload: payload,
            verifiedPackages: []
        )
    }

    public func decodePayload(data: Data) throws -> ContentPackagePayload {
        let payload: ContentPackagePayload
        do {
            payload = try ContentDocumentDecoder.decodePackage(data)
        } catch {
            throw BundledEssentialContentLoaderError.invalidPayload
        }
        guard payload.packageID == LaunchContent.essentialPackageID else {
            throw BundledEssentialContentLoaderError.packageIdentityMismatch(
                expected: LaunchContent.essentialPackageID,
                actual: payload.packageID
            )
        }
        return payload
    }
}
