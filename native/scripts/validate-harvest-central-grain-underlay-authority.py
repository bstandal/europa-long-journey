#!/usr/bin/env python3
"""Validate the byte-bound, non-shipping Harvest central-grain source input."""

from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
AUTHORITY_PATH = ROOT / "native/content/backstage/harvest/central-grain-underlay-v26.source-authority.json"
AUTHORITY_SIDECAR_PATH = AUTHORITY_PATH.with_suffix(AUTHORITY_PATH.suffix + ".sha256")
CONTRACT_PATH = ROOT / "native/design/phase1/harvest/layer-production-contract.json"
EXPECTED_AUTHORITY_SHA256 = "c2915382f8d52162540487d51e70ccafa6fd459969cf6c70c3da2cd1aae23eca"
EXPECTED_RECEIPT_SHA256 = "4ada27254650aae2ea7b139aff9ca87708928f7f42d7c159bbe275196c567be9"
EXPECTED_UNDERLAY_SHA256 = "de1b460d983c49cd337247cdd3ab58d56bde3cf28bd5eff633143ab17468114e"
EXPECTED_AUTHORIZATION_SHA256 = "11f7d1016bdc6a1ddd897f7283c35ffcacaf4510b4899c20bedf33b19b1500f9"


class AuthorityValidationError(RuntimeError):
    """Raised when a source input escapes its byte-bound non-shipping authority."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuthorityValidationError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def png_metadata(path: Path) -> tuple[int, int, int, int, bytes]:
    """Return width, height, bit depth, colour type and decompressed scanlines.

    The authority gate deliberately uses only the standard library so the
    repository validator runs in a clean Python installation as well as the
    bundled Codex runtime.
    """
    data = path.read_bytes()
    require(data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name}: PNG signature drifted")
    offset = 8
    ihdr: tuple[int, int, int, int, int] | None = None
    compressed = bytearray()
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        require(payload_end + 4 <= len(data), f"{path.name}: truncated PNG chunk")
        payload = data[payload_start:payload_end]
        if kind == b"IHDR":
            require(length == 13, f"{path.name}: invalid IHDR")
            width, height, bit_depth, colour_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            require(compression == 0 and filtering == 0, f"{path.name}: unsupported PNG codec")
            ihdr = (width, height, bit_depth, colour_type, interlace)
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
        offset = payload_end + 4
    require(ihdr is not None, f"{path.name}: IHDR missing")
    require(bool(compressed), f"{path.name}: IDAT missing")
    width, height, bit_depth, colour_type, interlace = ihdr
    require(interlace == 0, f"{path.name}: interlaced PNG unsupported by authority gate")
    return width, height, bit_depth, colour_type, zlib.decompress(bytes(compressed))


def unfiltered_gray8_pixels(path: Path) -> tuple[int, int, bytes]:
    width, height, bit_depth, colour_type, scanlines = png_metadata(path)
    require(bit_depth == 8 and colour_type == 0, f"{path.name}: 8-bit grayscale PNG required")
    stride = width
    require(len(scanlines) == height * (stride + 1), f"{path.name}: scanline bytes drifted")
    output = bytearray(width * height)
    previous = bytearray(stride)

    def paeth(left: int, above: int, upper_left: int) -> int:
        estimate = left + above - upper_left
        left_distance = abs(estimate - left)
        above_distance = abs(estimate - above)
        upper_left_distance = abs(estimate - upper_left)
        if left_distance <= above_distance and left_distance <= upper_left_distance:
            return left
        if above_distance <= upper_left_distance:
            return above
        return upper_left

    for row in range(height):
        start = row * (stride + 1)
        filter_type = scanlines[start]
        encoded = scanlines[start + 1 : start + 1 + stride]
        decoded = bytearray(stride)
        for column, value in enumerate(encoded):
            left = decoded[column - 1] if column > 0 else 0
            above = previous[column]
            upper_left = previous[column - 1] if column > 0 else 0
            predictor = {
                0: 0,
                1: left,
                2: above,
                3: (left + above) // 2,
                4: paeth(left, above, upper_left),
            }.get(filter_type)
            require(predictor is not None, f"{path.name}: unknown PNG filter")
            decoded[column] = (value + predictor) & 0xFF
        output[row * stride : (row + 1) * stride] = decoded
        previous = decoded
    return width, height, bytes(output)


def repository_file(record: dict[str, Any], location: str) -> Path:
    require(set(record) >= {"path", "sha256"}, f"{location}: path and sha256 required")
    path = (ROOT / record["path"]).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise AuthorityValidationError(f"{location}: path escaped repository") from error
    require(path.is_file(), f"{location}: file missing")
    require(sha256_file(path) == record["sha256"], f"{location}: SHA-256 drifted")
    if "bytes" in record:
        require(path.stat().st_size == record["bytes"], f"{location}: byte count drifted")
    return path


def central_underlay(contract: dict[str, Any]) -> dict[str, Any]:
    matches = [
        underlay
        for underlay in contract["disocclusionUnderlays"]
        if underlay.get("layerID") == "central-harvest"
    ]
    require(len(matches) == 1, "contract: exactly one central-harvest underlay required")
    return matches[0]


def validate_authority_document(authority: dict[str, Any], contract: dict[str, Any]) -> None:
    require(authority.get("schemaVersion") == 1, "authority.schemaVersion drifted")
    require(
        authority.get("status") == "CODEX_VISUAL_REVIEWED_NON_SHIPPING_SOURCE_INPUT",
        "authority.status drifted",
    )
    require(
        authority.get("scope") == "CENTRAL_HARVEST_DISOCCLUSION_UNDERLAY_ONLY",
        "authority.scope drifted",
    )

    limits = authority.get("authorityLimits", {})
    require(
        set(limits)
        == {
            "editorApproval",
            "productionAssetAuthority",
            "productionMasterAuthority",
            "packageAuthority",
            "shippingAllowed",
            "candidateMayEnterShippingCompiler",
        },
        "authorityLimits keys drifted",
    )
    require(not any(limits.values()), "source input claimed forbidden authority")

    underlay_contract = central_underlay(contract)
    recipe = underlay_contract["recipe"]
    require(recipe.get("status") == "MEASURED", "central-harvest recipe is not measured")
    require(recipe.get("sourceAuthority", {}).get("path") == AUTHORITY_PATH.relative_to(ROOT).as_posix(), "contract source-authority path drifted")
    require(recipe.get("sourceAuthority", {}).get("sha256") == EXPECTED_AUTHORITY_SHA256, "contract source-authority hash drifted")

    receipt_record = authority["technicalReceipt"]
    require(receipt_record.get("sha256") == EXPECTED_RECEIPT_SHA256, "technical receipt binding drifted")
    receipt_path = repository_file(receipt_record, "technicalReceipt")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    require(receipt.get("receiptID") == receipt_record.get("receiptID"), "technical receipt ID drifted")
    require(receipt.get("status") == "OBJECTIVE_TECHNICAL_QA_PASS", "technical receipt no longer passes")
    require(receipt_record.get("status") == receipt.get("status"), "authority receipt status drifted")
    require(receipt.get("failedGates") == [], "technical receipt contains failed gates")
    require(receipt_record.get("failedGates") == [], "authority claims different failed gates")
    receipt_sidecar = receipt_path.with_suffix(receipt_path.suffix + ".sha256")
    require(receipt_sidecar.read_text(encoding="utf-8").strip() == EXPECTED_RECEIPT_SHA256, "technical receipt sidecar drifted")

    specification = authority["specification"]
    repository_file(specification, "specification")
    require(receipt.get("specification") == specification, "technical receipt specification binding drifted")

    source_master = authority["sourceMaster"]
    source_master_path = repository_file(source_master, "sourceMaster")
    require(source_master["path"] == recipe["sourceMaster"]["path"], "contract source master path drifted")
    require(source_master["sha256"] == recipe["sourceMaster"]["sha256"], "contract source master hash drifted")
    require(source_master["cropPixels"] == recipe["cropPixels"], "source crop drifted")

    source_inputs = authority["sourceInputs"]
    underlay = source_inputs["underlay"]
    authorization = source_inputs["authorizationMask"]
    require(underlay["path"] == underlay_contract["sourceLayerPlatePath"], "contract underlay path drifted")
    require(authorization["path"] == recipe["authorizationMaskSourcePath"], "authorization path drifted")
    require(underlay["sha256"] == EXPECTED_UNDERLAY_SHA256, "underlay hash drifted")
    require(authorization["sha256"] == EXPECTED_AUTHORIZATION_SHA256, "authorization hash drifted")
    underlay_path = repository_file(underlay, "sourceInputs.underlay")
    authorization_path = repository_file(authorization, "sourceInputs.authorizationMask")

    receipt_outputs = receipt["outputs"]
    require(receipt_outputs["central-grain.png"]["sha256"] == underlay["sha256"], "receipt underlay hash drifted")
    require(receipt_outputs["central-grain-authorization.png"]["sha256"] == authorization["sha256"], "receipt authorization hash drifted")
    require(
        underlay_path.read_bytes()
        == (ROOT / receipt_outputs["central-grain.png"]["path"]).read_bytes(),
        "authority underlay is not byte-identical to r5c",
    )
    require(
        authorization_path.read_bytes()
        == (ROOT / receipt_outputs["central-grain-authorization.png"]["path"]).read_bytes(),
        "authority mask is not byte-identical to r5c",
    )

    underlay_width, underlay_height, underlay_depth, underlay_colour, _ = png_metadata(underlay_path)
    require(
        (underlay_width, underlay_height)
        == (underlay["pixelWidth"], underlay["pixelHeight"]),
        "underlay dimensions drifted",
    )
    require(
        underlay_depth == 8 and underlay_colour == 2 and underlay["colourModel"] == "RGB",
        "underlay colour model drifted",
    )
    authorization_width, authorization_height, authorization_pixels = unfiltered_gray8_pixels(
        authorization_path
    )
    require(
        (authorization_width, authorization_height)
        == (authorization["pixelWidth"], authorization["pixelHeight"]),
        "authorization dimensions drifted",
    )
    require(authorization["colourModel"] == "GRAYSCALE", "authorization colour model drifted")
    require(set(authorization_pixels) <= {0, 255}, "authorization mask is no longer binary")
    require(
        authorization_pixels.count(255)
        == authorization["nonzeroPixelCount"]
        == 196727,
        "authorization pixel count drifted",
    )

    recomposition = authority["initialStateRecomposition"]
    require(recomposition.get("restoreMask") == "AUTHORIZATION_T", "initial state must restore all of T")
    require(recomposition.get("semanticGrainMaskRole") == "MOVING_GRAIN_INPUT_ONLY", "semantic G role drifted")
    require(recomposition.get("maximumChannelDifference") == 0, "initial recomposition maximum drifted")
    require(recomposition.get("meanAbsoluteChannelDifference") == 0, "initial recomposition mean drifted")
    require(recomposition.get("exactPixelFraction") == 1, "initial recomposition is not exact")
    require(receipt["construction"]["target"]["writeMask"] == "AUTHORIZATION_T", "receipt write mask drifted")
    require(receipt["metrics"]["startingRecomposition"]["maximumChannelDifference"] == 0, "receipt recomposition maximum drifted")
    require(receipt["metrics"]["startingRecomposition"]["meanAbsoluteChannelDifference"] == 0, "receipt recomposition mean drifted")

    review = authority["visualReview"]
    require(review.get("status") == "TWO_INDEPENDENT_CODEX_VISUAL_REVIEWS_PASS", "visual review status drifted")
    require(len(review.get("inspectedReceiptOutputs", [])) == 9, "visual review set drifted")
    for name in review["inspectedReceiptOutputs"]:
        require(name in receipt_outputs, f"visual review output missing from receipt: {name}")
        repository_file(receipt_outputs[name], f"visualReview.{name}")
    require(review.get("findings") == {
        "stationaryGrainGhost": False,
        "hardBoundarySeam": False,
        "visibleDonorRepetition": False,
        "broadResidualReadsAs": "CLOTH_AND_SHADOW",
    }, "visual findings drifted")


def validate_authority() -> None:
    authority_bytes = AUTHORITY_PATH.read_bytes()
    require(sha256_bytes(authority_bytes) == EXPECTED_AUTHORITY_SHA256, "source-authority bytes drifted")
    require(AUTHORITY_SIDECAR_PATH.read_text(encoding="utf-8").strip() == EXPECTED_AUTHORITY_SHA256, "source-authority sidecar drifted")
    authority = json.loads(authority_bytes)
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    validate_authority_document(authority, contract)


def main() -> int:
    validate_authority()
    print("Harvest central-grain source authority is byte-bound and non-shipping; editor, production-master, package and shipping authority remain absent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
