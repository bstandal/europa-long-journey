import Foundation

/// One stable public-copy key and its editor-approved launch text.
///
/// The ID survives copy edits and is the join key for a future locale-specific
/// catalogue. Only the English launch value ships in the initial product.
public struct LocalizedStringSpec: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: LocalizedStringID
    public let launchEnglish: String

    public init(id: LocalizedStringID, launchEnglish: String) {
        self.id = id
        self.launchEnglish = launchEnglish
    }

    public func validate(field: String) throws {
        try requireNonempty(id, field: "\(field).id")
        guard !launchEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "\(field).launchEnglish",
                reason: "editor-approved English launch text is required"
            )
        }
    }
}

func requireConsistentLocalizedStrings(
    _ strings: [LocalizedStringSpec],
    field: String
) throws {
    var valueByID: [LocalizedStringID: String] = [:]
    for string in strings {
        try string.validate(field: field)
        if let existing = valueByID[string.id], existing != string.launchEnglish {
            throw ContentValidationError.invalidValue(
                field: field,
                reason: "localized string ID '\(string.id)' has conflicting English launch values"
            )
        }
        valueByID[string.id] = string.launchEnglish
    }
}
