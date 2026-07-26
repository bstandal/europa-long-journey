import CryptoKit
import CoreFoundation
import Foundation

/// Detects a newer durable authority before the current decoder filters it
/// out as invalid. A current-envelope future payload is accepted as an
/// authority only when its raw canonical digest matches. A future envelope
/// may use a digest algorithm this runtime does not understand, so its
/// generation/header is preserved fail-closed instead of being overwritten.
struct TwoSlotFutureAuthority: Equatable, Sendable {
    let generation: UInt64
    let requiredFormatVersion: Int

    static func inspect(
        data: Data,
        payloadKey: String,
        currentEnvelopeFormatVersion: Int,
        currentPayloadFormatVersion: Int
    ) -> TwoSlotFutureAuthority? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelopeVersion = exactInteger(root["envelopeFormatVersion"]),
              let generation = exactUnsignedInteger(root["generation"]),
              generation > 0,
              let digest = root["digest"] as? String,
              isLowercaseSHA256(digest),
              let payload = root[payloadKey] as? [String: Any],
              let payloadVersion = exactInteger(payload["formatVersion"]) else {
            return nil
        }

        if envelopeVersion > currentEnvelopeFormatVersion {
            return TwoSlotFutureAuthority(
                generation: generation,
                requiredFormatVersion: max(envelopeVersion, payloadVersion)
            )
        }
        guard envelopeVersion == currentEnvelopeFormatVersion,
              payloadVersion > currentPayloadFormatVersion,
              rawDigestMatches(
                  envelopeVersion: envelopeVersion,
                  generation: generation,
                  payloadKey: payloadKey,
                  payload: payload,
                  expectedDigest: digest
              ) else {
            return nil
        }
        return TwoSlotFutureAuthority(
            generation: generation,
            requiredFormatVersion: payloadVersion
        )
    }

    private static func rawDigestMatches(
        envelopeVersion: Int,
        generation: UInt64,
        payloadKey: String,
        payload: [String: Any],
        expectedDigest: String
    ) -> Bool {
        let material: [String: Any] = [
            "envelopeFormatVersion": envelopeVersion,
            "generation": generation,
            payloadKey: payload,
        ]
        guard JSONSerialization.isValidJSONObject(material),
              let canonical = try? JSONSerialization.data(
                  withJSONObject: material,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              ) else {
            return false
        }
        return SHA256.hash(data: canonical)
            .map { String(format: "%02x", $0) }
            .joined() == expectedDigest
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(Int.min), double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private static func exactUnsignedInteger(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let decimal = number.stringValue
        guard !decimal.hasPrefix("-"),
              !decimal.contains("."),
              !decimal.lowercased().contains("e") else {
            return nil
        }
        return UInt64(decimal)
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}
