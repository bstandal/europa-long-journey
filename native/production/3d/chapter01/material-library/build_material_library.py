#!/usr/bin/env python3
"""Build the pinned Chapter 01 mobile PBR candidate library.

The manifest is authoritative. This tool downloads only its exact Poly Haven
files, verifies every byte and image dimension, and emits an uncompressed ZIP
with stable entry order, metadata and timestamps. JPEG source maps are already
compressed, so ZIP_STORED avoids needless work and zlib-version drift.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import time
from typing import Any, Iterable
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import zipfile


LIBRARY_ROOT = Path(__file__).resolve().parent
MANIFEST_PATH = LIBRARY_ROOT / "material-library-manifest.json"
GENERATED_ROOT = LIBRARY_ROOT / "generated"
UNPACKED_ROOT = GENERATED_ROOT / "unpacked"
ARCHIVE_PATH = GENERATED_ROOT / "chapter01-mobile-pbr-materials-v1.zip"
RECEIPT_PATH = GENERATED_ROOT / "build-receipt.json"

EXPECTED_ROLES = {"soil", "rock", "timber", "cloth", "reed-thatch"}
EXPECTED_CHANNELS = {"baseColor", "normal", "roughness"}
EXPECTED_DOWNLOAD_HOST = "dl.polyhaven.org"
EXPECTED_LICENSE_EVIDENCE = "https://polyhaven.com/license"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
USER_AGENT = "The-Long-West-Chapter01-Material-Builder/1.0"


class BuildError(RuntimeError):
    """A source, rights, manifest or reproducibility gate failed."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def read_manifest() -> tuple[dict[str, Any], bytes]:
    raw = MANIFEST_PATH.read_bytes()
    try:
        manifest = json.loads(raw)
    except json.JSONDecodeError as error:
        raise BuildError(f"Manifest is not valid JSON: {error}") from error
    validate_manifest(manifest)
    return manifest, raw


def validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("schemaVersion") != 1:
        raise BuildError("Unsupported material-library schemaVersion")
    if manifest.get("libraryID") != "chapter01-mobile-pbr-materials-v1":
        raise BuildError("Unexpected libraryID")
    if manifest.get("classification") != "MATERIAL_CANDIDATE":
        raise BuildError("Library must remain MATERIAL_CANDIDATE")
    if manifest.get("finalArtGate") != "OPEN":
        raise BuildError("The final art gate must remain OPEN")
    if manifest.get("shippingStatus") != "BLOCKED":
        raise BuildError("Candidate library may not claim shipping approval")
    if manifest.get("incrementalCostNOK") != 0:
        raise BuildError("Material library must require no incremental cost")
    if manifest.get("externalHumanContributor") is not False:
        raise BuildError("External human contributors are not permitted")

    source_policy = manifest.get("sourcePolicy", {})
    if source_policy.get("provider") != "Poly Haven":
        raise BuildError("Only the approved Poly Haven source is permitted")
    if source_policy.get("assetLicense") != "CC0-1.0":
        raise BuildError("Every source asset must be CC0-1.0")
    if source_policy.get("licenseEvidenceURL") != EXPECTED_LICENSE_EVIDENCE:
        raise BuildError("Poly Haven license evidence URL is missing or changed")
    if source_policy.get("rightsDecision") != "PASS":
        raise BuildError("Rights decision did not pass")
    for permission in (
        "commercialUseAllowed",
        "redistributionAllowed",
    ):
        if source_policy.get(permission) is not True:
            raise BuildError(f"Required right is absent: {permission}")
    if source_policy.get("attributionRequired") is not False:
        raise BuildError("Unexpected attribution requirement")

    mobile_profile = manifest.get("mobileProfile", {})
    if mobile_profile.get("resolutionClass") != "1K":
        raise BuildError("Only the 1K mobile profile is accepted")
    if set(mobile_profile.get("runtimeChannels", [])) != EXPECTED_CHANNELS:
        raise BuildError("Mobile profile must contain exactly three PBR channels")
    if mobile_profile.get("normalConvention") != "OpenGL +Y":
        raise BuildError("Normal maps must use the OpenGL +Y convention")
    if mobile_profile.get("metallicConstant") != 0.0:
        raise BuildError("Organic and mineral candidates must remain dielectric")

    materials = manifest.get("materials")
    if not isinstance(materials, list) or len(materials) != len(EXPECTED_ROLES):
        raise BuildError("Expected exactly five material candidates")

    material_ids: set[str] = set()
    slugs: set[str] = set()
    roles: set[str] = set()
    output_paths: set[str] = set()
    for material in materials:
        material_id = material.get("materialID")
        slug = material.get("sourceAssetSlug")
        role = material.get("role")
        if not isinstance(material_id, str) or not material_id:
            raise BuildError("A materialID is missing")
        if material_id in material_ids:
            raise BuildError(f"Duplicate materialID: {material_id}")
        material_ids.add(material_id)
        if not isinstance(slug, str) or not slug:
            raise BuildError(f"Source slug is missing for {material_id}")
        if slug in slugs:
            raise BuildError(f"Duplicate source asset slug: {slug}")
        slugs.add(slug)
        roles.add(role)

        if material.get("license") != "CC0-1.0":
            raise BuildError(f"Unclear or non-CC0 license for {material_id}")
        if material.get("rightsStatus") != "COMMERCIAL_USE_CLEARED":
            raise BuildError(f"Rights are not cleared for {material_id}")
        authors = material.get("authors")
        if not isinstance(authors, list) or not authors:
            raise BuildError(f"Author provenance is missing for {material_id}")
        for author in authors:
            if not author.get("name") or not author.get("role"):
                raise BuildError(f"Incomplete author provenance for {material_id}")

        expected_page = f"https://polyhaven.com/a/{slug}"
        expected_info = f"https://api.polyhaven.com/info/{slug}"
        expected_files = f"https://api.polyhaven.com/files/{slug}"
        if material.get("sourcePage") != expected_page:
            raise BuildError(f"Unexpected source page for {material_id}")
        if material.get("sourceMetadataURL") != expected_info:
            raise BuildError(f"Unexpected metadata URL for {material_id}")
        if material.get("sourceFileIndexURL") != expected_files:
            raise BuildError(f"Unexpected file index URL for {material_id}")
        if not material.get("historicalUseBoundary"):
            raise BuildError(f"Historical-use boundary is missing for {material_id}")

        maps = material.get("maps")
        if not isinstance(maps, list) or len(maps) != 3:
            raise BuildError(f"Expected three maps for {material_id}")
        channels = {entry.get("channel") for entry in maps}
        if channels != EXPECTED_CHANNELS:
            raise BuildError(f"Unexpected map channels for {material_id}: {channels}")
        for entry in maps:
            validate_map_entry(material_id, slug, entry, output_paths)

    if roles != EXPECTED_ROLES:
        raise BuildError(f"Material roles do not match the requested set: {roles}")

    cloth = next(item for item in materials if item["role"] == "cloth")
    approval = cloth.get("channelApproval", {})
    if approval.get("baseColor") != "REFERENCE_ONLY":
        raise BuildError("Blue cloth base colour must remain reference-only")
    if approval.get("normal") != "MATERIAL_CANDIDATE":
        raise BuildError("Cloth normal-map candidate status is missing")
    if approval.get("roughness") != "MATERIAL_CANDIDATE":
        raise BuildError("Cloth roughness-map candidate status is missing")


def validate_map_entry(
    material_id: str,
    slug: str,
    entry: dict[str, Any],
    output_paths: set[str],
) -> None:
    channel = entry.get("channel")
    source_key = entry.get("sourceMapKey")
    expected_key = {
        "baseColor": "Diffuse",
        "normal": "nor_gl",
        "roughness": "Rough",
    }.get(channel)
    if source_key != expected_key:
        raise BuildError(f"Unexpected Poly Haven map key for {material_id}/{channel}")

    output = entry.get("outputPath")
    if not isinstance(output, str):
        raise BuildError(f"Output path is missing for {material_id}/{channel}")
    pure_output = PurePosixPath(output)
    expected_output = PurePosixPath("materials") / material_id / f"{channel}.jpg"
    if pure_output != expected_output or pure_output.is_absolute() or ".." in pure_output.parts:
        raise BuildError(f"Unsafe or unexpected output path: {output}")
    if output in output_paths:
        raise BuildError(f"Duplicate output path: {output}")
    output_paths.add(output)

    url = entry.get("downloadURL")
    parsed = urlparse(url) if isinstance(url, str) else None
    if (
        parsed is None
        or parsed.scheme != "https"
        or parsed.hostname != EXPECTED_DOWNLOAD_HOST
        or f"/1k/{slug}/" not in parsed.path
    ):
        raise BuildError(f"Unapproved download URL for {material_id}/{channel}")

    if not isinstance(entry.get("byteCount"), int) or entry["byteCount"] <= 0:
        raise BuildError(f"Invalid byte count for {material_id}/{channel}")
    for algorithm, expected_length in (("sourceMD5", 32), ("sha256", 64)):
        digest = entry.get(algorithm)
        if (
            not isinstance(digest, str)
            or len(digest) != expected_length
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            raise BuildError(f"Invalid {algorithm} for {material_id}/{channel}")

    width = entry.get("width")
    height = entry.get("height")
    if width != 1024 or not isinstance(height, int) or not 1024 <= height <= 1026:
        raise BuildError(f"Map is outside the pinned 1K dimensions: {material_id}/{channel}")
    expected_color_space = "sRGB" if channel == "baseColor" else "linear"
    if entry.get("colorSpace") != expected_color_space:
        raise BuildError(f"Incorrect colour space for {material_id}/{channel}")
    if channel == "normal" and entry.get("normalConvention") != "OpenGL +Y":
        raise BuildError(f"Incorrect normal convention for {material_id}")


def download_bytes(url: str) -> bytes:
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            request = Request(url, headers={"User-Agent": USER_AGENT})
            with urlopen(request, timeout=60) as response:
                final_host = urlparse(response.geturl()).hostname
                if final_host != EXPECTED_DOWNLOAD_HOST:
                    raise BuildError(f"Download redirected to unapproved host: {final_host}")
                return response.read()
        except Exception as error:  # Network errors need their original context.
            last_error = error
            if attempt < 2:
                time.sleep(0.5 * (attempt + 1))
    raise BuildError(f"Download failed after three attempts: {url}: {last_error}")


def jpeg_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        raise BuildError("Downloaded map is not a JPEG")
    start_of_frame_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }
    cursor = 2
    while cursor < len(data):
        if data[cursor] != 0xFF:
            cursor += 1
            continue
        while cursor < len(data) and data[cursor] == 0xFF:
            cursor += 1
        if cursor >= len(data):
            break
        marker = data[cursor]
        cursor += 1
        if marker in {0x01, 0xD8, 0xD9}:
            continue
        if cursor + 2 > len(data):
            break
        segment_length = int.from_bytes(data[cursor : cursor + 2], "big")
        if segment_length < 2 or cursor + segment_length > len(data):
            break
        if marker in start_of_frame_markers:
            if segment_length < 7:
                break
            height = int.from_bytes(data[cursor + 3 : cursor + 5], "big")
            width = int.from_bytes(data[cursor + 5 : cursor + 7], "big")
            return width, height
        cursor += segment_length
    raise BuildError("JPEG dimensions could not be read")


def verified_source_maps(manifest: dict[str, Any]) -> dict[str, bytes]:
    verified: dict[str, bytes] = {}
    for material in manifest["materials"]:
        for entry in material["maps"]:
            output = entry["outputPath"]
            data = download_bytes(entry["downloadURL"])
            if len(data) != entry["byteCount"]:
                raise BuildError(
                    f"Byte count mismatch for {output}: "
                    f"expected {entry['byteCount']}, got {len(data)}"
                )
            md5 = hashlib.md5(data, usedforsecurity=False).hexdigest()
            if md5 != entry["sourceMD5"]:
                raise BuildError(f"Poly Haven MD5 mismatch for {output}")
            digest = sha256_bytes(data)
            if digest != entry["sha256"]:
                raise BuildError(f"Pinned SHA-256 mismatch for {output}")
            dimensions = jpeg_dimensions(data)
            expected_dimensions = (entry["width"], entry["height"])
            if dimensions != expected_dimensions:
                raise BuildError(
                    f"Dimension mismatch for {output}: "
                    f"expected {expected_dimensions}, got {dimensions}"
                )
            verified[output] = data
    return verified


def package_entries(
    manifest: dict[str, Any], source_maps: dict[str, bytes]
) -> dict[str, bytes]:
    manifest_bytes = canonical_json_bytes(manifest)
    entries = {"manifest.json": manifest_bytes, **source_maps}
    sums = [
        f"{sha256_bytes(data)}  {path}"
        for path, data in sorted(entries.items())
    ]
    entries["SHA256SUMS"] = ("\n".join(sums) + "\n").encode("utf-8")
    return entries


def deterministic_zip_bytes(entries: dict[str, bytes], destination: Path) -> bytes:
    with zipfile.ZipFile(destination, "w", allowZip64=True) as archive:
        for path, data in sorted(entries.items()):
            info = zipfile.ZipInfo(path, ZIP_TIMESTAMP)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.flag_bits = 0
            archive.writestr(info, data)
    return destination.read_bytes()


def write_unpacked(entries: dict[str, bytes], destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    resolved_destination = destination.resolve()
    for relative_path, data in sorted(entries.items()):
        target = destination.joinpath(*PurePosixPath(relative_path).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        if resolved_destination not in target.resolve().parents:
            raise BuildError(f"Refusing to write outside generated output: {target}")
        target.write_bytes(data)


def safe_replace_unpacked(staged: Path) -> None:
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)
    if UNPACKED_ROOT.is_symlink():
        raise BuildError("Refusing to replace a symlinked generated/unpacked path")
    if UNPACKED_ROOT.exists():
        if UNPACKED_ROOT.parent.resolve() != GENERATED_ROOT.resolve():
            raise BuildError("Refusing to remove an unexpected directory")
        shutil.rmtree(UNPACKED_ROOT)
    os.replace(staged, UNPACKED_ROOT)


def write_receipt(
    manifest: dict[str, Any],
    raw_manifest: bytes,
    entries: dict[str, bytes],
    archive_data: bytes,
) -> dict[str, Any]:
    receipt = {
        "schemaVersion": 1,
        "libraryID": manifest["libraryID"],
        "classification": manifest["classification"],
        "shippingStatus": manifest["shippingStatus"],
        "finalArtGate": manifest["finalArtGate"],
        "rightsDecision": manifest["sourcePolicy"]["rightsDecision"],
        "sourceManifestSHA256": sha256_bytes(raw_manifest),
        "packagedManifestSHA256": sha256_bytes(entries["manifest.json"]),
        "materialCount": len(manifest["materials"]),
        "mapCount": sum(len(item["maps"]) for item in manifest["materials"]),
        "archive": {
            "path": ARCHIVE_PATH.name,
            "byteCount": len(archive_data),
            "sha256": sha256_bytes(archive_data),
            "compression": "ZIP_STORED",
        },
        "reproducibility": {
            "independentArchivesCompared": 2,
            "byteIdentical": True,
            "volatileMetadataIncluded": False,
        },
    }
    RECEIPT_PATH.write_bytes(canonical_json_bytes(receipt))
    return receipt


def build() -> dict[str, Any]:
    manifest, raw_manifest = read_manifest()
    source_maps = verified_source_maps(manifest)
    entries = package_entries(manifest, source_maps)
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix="chapter01-material-build-", dir=LIBRARY_ROOT
    ) as temporary_directory:
        temporary_root = Path(temporary_directory)
        archive_a = temporary_root / "candidate-a.zip"
        archive_b = temporary_root / "candidate-b.zip"
        data_a = deterministic_zip_bytes(entries, archive_a)
        data_b = deterministic_zip_bytes(entries, archive_b)
        if data_a != data_b:
            raise BuildError("Two independent package builds were not byte-identical")

        staged_unpacked = temporary_root / "unpacked"
        write_unpacked(entries, staged_unpacked)
        safe_replace_unpacked(staged_unpacked)
        ARCHIVE_PATH.write_bytes(data_a)

    receipt = write_receipt(manifest, raw_manifest, entries, data_a)
    verify_generated(manifest, receipt)
    return receipt


def all_map_entries(manifest: dict[str, Any]) -> Iterable[dict[str, Any]]:
    for material in manifest["materials"]:
        yield from material["maps"]


def verify_generated(
    manifest: dict[str, Any] | None = None,
    receipt: dict[str, Any] | None = None,
) -> None:
    if manifest is None:
        manifest, _ = read_manifest()
    if receipt is None:
        try:
            receipt = json.loads(RECEIPT_PATH.read_bytes())
        except (FileNotFoundError, json.JSONDecodeError) as error:
            raise BuildError(f"Generated build receipt is unavailable: {error}") from error

    if not ARCHIVE_PATH.is_file() or not UNPACKED_ROOT.is_dir():
        raise BuildError("Generated archive or unpacked library is missing")
    archive_data = ARCHIVE_PATH.read_bytes()
    if sha256_bytes(archive_data) != receipt["archive"]["sha256"]:
        raise BuildError("Generated archive does not match its receipt")
    if len(archive_data) != receipt["archive"]["byteCount"]:
        raise BuildError("Generated archive byte count does not match its receipt")

    expected_paths = {"manifest.json", "SHA256SUMS"}
    expected_paths.update(entry["outputPath"] for entry in all_map_entries(manifest))
    with zipfile.ZipFile(ARCHIVE_PATH, "r") as archive:
        names = set(archive.namelist())
        if names != expected_paths:
            raise BuildError("Generated archive contains missing or unexpected files")
        for path in sorted(expected_paths):
            archived = archive.read(path)
            unpacked = (UNPACKED_ROOT / path).read_bytes()
            if archived != unpacked:
                raise BuildError(f"Archive and unpacked output differ: {path}")
        if archive.read("manifest.json") != canonical_json_bytes(manifest):
            raise BuildError("Generated archive contains the wrong manifest")

    for entry in all_map_entries(manifest):
        data = (UNPACKED_ROOT / entry["outputPath"]).read_bytes()
        if sha256_bytes(data) != entry["sha256"]:
            raise BuildError(f"Generated map hash mismatch: {entry['outputPath']}")
        if jpeg_dimensions(data) != (entry["width"], entry["height"]):
            raise BuildError(f"Generated map dimensions changed: {entry['outputPath']}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--manifest-only",
        action="store_true",
        help="Validate the checked-in manifest without downloading source maps.",
    )
    mode.add_argument(
        "--verify-generated",
        action="store_true",
        help="Verify the existing generated package without network access.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.manifest_only:
            manifest, _ = read_manifest()
            print(
                f"PASS {manifest['libraryID']}: "
                f"{len(manifest['materials'])} CC0 material candidates"
            )
        elif arguments.verify_generated:
            verify_generated()
            print(f"PASS generated package: {ARCHIVE_PATH}")
        else:
            receipt = build()
            print(
                "PASS "
                f"{receipt['libraryID']}: "
                f"{receipt['materialCount']} materials, "
                f"{receipt['mapCount']} maps, "
                f"archive sha256 {receipt['archive']['sha256']}"
            )
        return 0
    except (BuildError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"FAIL: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
