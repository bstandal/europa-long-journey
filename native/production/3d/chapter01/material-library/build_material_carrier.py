#!/usr/bin/env python3
"""Build and validate the deterministic Chapter 01 material-carrier USDZ."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Any
import zipfile

sys.dont_write_bytecode = True
import build_material_library as source_library


ROOT = Path(__file__).resolve().parent
SOURCE_USDA = ROOT / "chapter01-material-carrier.usda"
CONTRACT_PATH = ROOT / "material-carrier-contract.json"
GENERATED_ROOT = ROOT / "generated"
OUTPUT_ROOT = GENERATED_ROOT / "carrier"
OUTPUT_USDZ = OUTPUT_ROOT / "chapter01-material-carrier-v1.usdz"
OUTPUT_RECEIPT = OUTPUT_ROOT / "build-receipt.json"
OUTPUT_SUMS = OUTPUT_ROOT / "SHA256SUMS"
REALITYKIT_VERIFIER = ROOT / "verify_material_carrier.swift"
USDCAT = Path("/usr/bin/usdcat")
USDCHECKER = Path("/usr/bin/usdchecker")
XCRUN = Path("/usr/bin/xcrun")
ROOT_MEMBER = "chapter01-material-carrier-v1.usdc"
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)

EXPECTED_ROLES = {
    "soil",
    "dark-rock",
    "timber",
    "cloth-neutral",
    "thatch",
}
EXPECTED_MATERIAL_PRIMS = {
    "/Chapter01MaterialCarrier/Materials/M_CH01_Soil",
    "/Chapter01MaterialCarrier/Materials/M_CH01_DarkRock",
    "/Chapter01MaterialCarrier/Materials/M_CH01_Timber",
    "/Chapter01MaterialCarrier/Materials/M_CH01_ClothNeutral",
    "/Chapter01MaterialCarrier/Materials/M_CH01_Thatch",
}


class CarrierBuildError(RuntimeError):
    """The carrier source, package or validation gate failed."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def load_contract() -> tuple[dict[str, Any], bytes]:
    raw = CONTRACT_PATH.read_bytes()
    try:
        contract = json.loads(raw)
    except json.JSONDecodeError as error:
        raise CarrierBuildError(f"Carrier contract is not valid JSON: {error}") from error
    validate_contract(contract)
    return contract, raw


def validate_contract(contract: dict[str, Any]) -> None:
    if contract.get("schemaVersion") != 1:
        raise CarrierBuildError("Unsupported material-carrier schemaVersion")
    if contract.get("carrierID") != "chapter01-material-carrier-v1":
        raise CarrierBuildError("Unexpected carrierID")
    if contract.get("classification") != "MATERIAL_CANDIDATE":
        raise CarrierBuildError("Carrier must remain MATERIAL_CANDIDATE")
    if contract.get("shippingStatus") != "BLOCKED":
        raise CarrierBuildError("Carrier may not claim shipping approval")
    if contract.get("finalArtGate") != "OPEN":
        raise CarrierBuildError("Carrier finalArtGate must remain OPEN")
    if contract.get("sourceLibraryID") != "chapter01-mobile-pbr-materials-v1":
        raise CarrierBuildError("Carrier source library changed")
    if contract.get("rootPrimPath") != "/Chapter01MaterialCarrier":
        raise CarrierBuildError("Carrier root prim path changed")

    materials = contract.get("materials")
    if not isinstance(materials, list) or len(materials) != 5:
        raise CarrierBuildError("Carrier must expose exactly five material families")
    roles = {item.get("role") for item in materials}
    if roles != EXPECTED_ROLES:
        raise CarrierBuildError(f"Unexpected carrier material roles: {roles}")
    prims = {item.get("materialPrimPath") for item in materials}
    if prims != EXPECTED_MATERIAL_PRIMS:
        raise CarrierBuildError(f"Stable material prim paths changed: {prims}")

    swatches: set[str] = set()
    source_paths: set[str] = set()
    package_paths: set[str] = set()
    for material in materials:
        swatch = material.get("swatchEntityName")
        if not isinstance(swatch, str) or not swatch.startswith("Swatch_"):
            raise CarrierBuildError(f"Invalid swatch entity name: {swatch}")
        if swatch in swatches:
            raise CarrierBuildError(f"Duplicate swatch entity: {swatch}")
        swatches.add(swatch)
        bindings = material.get("textureBindings")
        if not isinstance(bindings, list) or not bindings:
            raise CarrierBuildError(f"Texture bindings missing for role {material['role']}")
        expected_channels = (
            {"normal", "roughness"}
            if material["role"] == "cloth-neutral"
            else {"baseColor", "normal", "roughness"}
        )
        channels = {binding.get("channel") for binding in bindings}
        if channels != expected_channels:
            raise CarrierBuildError(
                f"Unexpected channels for {material['role']}: {channels}"
            )
        for binding in bindings:
            source_path = binding.get("sourcePath")
            package_path = binding.get("packagePath")
            validate_relative_path(source_path, "sourcePath")
            validate_relative_path(package_path, "packagePath")
            if not str(source_path).startswith("materials/"):
                raise CarrierBuildError(f"Unexpected source map path: {source_path}")
            if not str(package_path).startswith("textures/"):
                raise CarrierBuildError(f"Unexpected package map path: {package_path}")
            if source_path in source_paths or package_path in package_paths:
                raise CarrierBuildError("Duplicate source or package texture path")
            source_paths.add(source_path)
            package_paths.add(package_path)

    cloth = next(item for item in materials if item["role"] == "cloth-neutral")
    if cloth.get("sourceBaseColorPolicy") != "REFERENCE_ONLY_NOT_PACKAGED":
        raise CarrierBuildError("The blue cloth source base colour must not be packaged")
    if cloth.get("authoredBaseColorLinearRGB") != [0.42, 0.31, 0.2]:
        raise CarrierBuildError("Authored neutral cloth treatment changed")

    integration = contract.get("signedV2ReviewIntegration", {})
    if integration.get("assetID") != "asset-first-farmers-material-carrier-v1":
        raise CarrierBuildError("Unexpected signed V2 carrier assetID")
    if integration.get("assetKind") != "material":
        raise CarrierBuildError("Carrier V2 asset kind must be material")
    if integration.get("domainContractImpact") != "NONE":
        raise CarrierBuildError("Carrier may not alter the domain contract")
    if len(integration.get("replaceFakePaths", [])) != 5:
        raise CarrierBuildError("Five fake material paths must be named for replacement")


def validate_relative_path(value: Any, label: str) -> None:
    if not isinstance(value, str):
        raise CarrierBuildError(f"Missing {label}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or str(path) != value:
        raise CarrierBuildError(f"Unsafe {label}: {value}")


def source_map_index(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for material in manifest["materials"]:
        for mapping in material["maps"]:
            result[mapping["outputPath"]] = mapping
    return result


def verify_source_library(
    contract: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest, raw_manifest = source_library.read_manifest()
    if manifest["libraryID"] != contract["sourceLibraryID"]:
        raise CarrierBuildError("Carrier and source library IDs differ")
    actual_manifest_hash = sha256_bytes(raw_manifest)
    if actual_manifest_hash != contract["sourceManifestSHA256"]:
        raise CarrierBuildError(
            "Source material manifest changed; review and update the carrier contract"
        )
    source_library.verify_generated(manifest)
    indexed = source_map_index(manifest)
    for material in contract["materials"]:
        for binding in material["textureBindings"]:
            source_path = binding["sourcePath"]
            source_record = indexed.get(source_path)
            if source_record is None:
                raise CarrierBuildError(f"Carrier map is absent from source manifest: {source_path}")
            source_file = source_library.UNPACKED_ROOT / source_path
            if not source_file.is_file():
                raise CarrierBuildError(f"Verified source map is missing: {source_file}")
            if sha256_file(source_file) != source_record["sha256"]:
                raise CarrierBuildError(f"Source map hash changed: {source_path}")
    return manifest, indexed


def validate_usda_source(contract: dict[str, Any]) -> None:
    source = SOURCE_USDA.read_text(encoding="utf-8")
    material_names = set(re.findall(r'def Material "([A-Za-z0-9_]+)"', source))
    expected_names = {PurePosixPath(path).name for path in EXPECTED_MATERIAL_PRIMS}
    if material_names != expected_names:
        raise CarrierBuildError(f"USDA material prims changed: {material_names}")
    for material in contract["materials"]:
        swatch = material["swatchEntityName"]
        if f'def Mesh "{swatch}"' not in source:
            raise CarrierBuildError(f"USDA swatch is missing: {swatch}")

    asset_references = set(re.findall(r"@([^@]+)@", source))
    expected_references = {
        f"./{binding['packagePath']}"
        for material in contract["materials"]
        for binding in material["textureBindings"]
    }
    if asset_references != expected_references:
        raise CarrierBuildError(
            f"USDA package-relative texture references changed: {asset_references}"
        )
    if any(url.startswith(("/", "http://", "https://")) for url in asset_references):
        raise CarrierBuildError("USDA contains an external or absolute asset reference")
    if "cloth-neutral/baseColor" in source or "cloth-rough-weave-v1/baseColor" in source:
        raise CarrierBuildError("Reference-only blue cloth base colour entered the carrier")
    if 'color3f inputs:diffuseColor = (0.42, 0.31, 0.20)' not in source:
        raise CarrierBuildError("Authored neutral cloth base colour is missing")
    if 'custom string finalArtGate = "OPEN"' not in source:
        raise CarrierBuildError("USDA final art gate is not open")


def run_checked(command: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        output = "\n".join(part for part in (result.stdout, result.stderr) if part)
        raise CarrierBuildError(
            f"Command failed ({result.returncode}): {' '.join(command)}\n{output}"
        )
    return "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())


def copy_texture_payloads(contract: dict[str, Any], destination: Path) -> None:
    for material in contract["materials"]:
        for binding in material["textureBindings"]:
            source = source_library.UNPACKED_ROOT / binding["sourcePath"]
            target = destination.joinpath(*PurePosixPath(binding["packagePath"]).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())


def usdzip_extra(current_offset: int, member_name: str) -> bytes:
    name_length = len(member_name.encode("utf-8"))
    header_without_extra = current_offset + 30 + name_length
    padding = (-header_without_extra) % 64
    if 0 < padding < 4:
        padding += 64
    if padding == 0:
        return b""
    return struct.pack("<HH", 0xFFFF, padding - 4) + bytes(padding - 4)


def write_deterministic_usdz(
    root_usdc: Path,
    contract: dict[str, Any],
    staging_root: Path,
    destination: Path,
) -> None:
    members = [(ROOT_MEMBER, root_usdc.read_bytes())]
    texture_paths = sorted(
        binding["packagePath"]
        for material in contract["materials"]
        for binding in material["textureBindings"]
    )
    members.extend(
        (path, staging_root.joinpath(*PurePosixPath(path).parts).read_bytes())
        for path in texture_paths
    )

    with zipfile.ZipFile(destination, "w", allowZip64=True) as archive:
        for member_name, data in members:
            if archive.fp is None:
                raise CarrierBuildError("USDZ archive stream is unavailable")
            info = zipfile.ZipInfo(member_name, FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.extra = usdzip_extra(archive.fp.tell(), member_name)
            archive.writestr(info, data)


def verify_usdz_structure(
    package: Path, contract: dict[str, Any]
) -> list[dict[str, Any]]:
    expected = [ROOT_MEMBER] + sorted(
        binding["packagePath"]
        for material in contract["materials"]
        for binding in material["textureBindings"]
    )
    records: list[dict[str, Any]] = []
    with zipfile.ZipFile(package) as archive:
        members = archive.infolist()
        names = [member.filename for member in members]
        if names != expected:
            raise CarrierBuildError(f"Unexpected USDZ member order: {names}")
        for member in members:
            if member.compress_type != zipfile.ZIP_STORED:
                raise CarrierBuildError(f"Compressed USDZ member: {member.filename}")
            data_offset = (
                member.header_offset
                + 30
                + len(member.filename.encode("utf-8"))
                + len(member.extra)
            )
            if data_offset % 64 != 0:
                raise CarrierBuildError(
                    f"USDZ member is not 64-byte aligned: {member.filename} at {data_offset}"
                )
            data = archive.read(member)
            records.append(
                {
                    "path": member.filename,
                    "byteCount": len(data),
                    "sha256": sha256_bytes(data),
                    "dataOffset": data_offset,
                }
            )
    return records


def build_once(destination: Path, contract: dict[str, Any]) -> tuple[Path, Path]:
    destination.mkdir(parents=True, exist_ok=False)
    copy_texture_payloads(contract, destination)
    usdc = destination / ROOT_MEMBER
    run_checked([str(USDCAT), str(SOURCE_USDA), "-o", str(usdc)])
    usdz = destination / "chapter01-material-carrier-v1.usdz"
    write_deterministic_usdz(usdc, contract, destination, usdz)
    verify_usdz_structure(usdz, contract)
    return usdc, usdz


def verify_arkit(package: Path) -> str:
    output = run_checked([str(USDCHECKER), "--arkit", "-t", str(package)])
    if "Success" not in output:
        raise CarrierBuildError(f"usdchecker did not report success:\n{output}")
    return output


def verify_realitykit(package: Path) -> str:
    output = run_checked(
        [str(XCRUN), "swift", str(REALITYKIT_VERIFIER), str(package)]
    )
    if "PASS RealityKit offline import" not in output:
        raise CarrierBuildError(f"RealityKit verifier did not report success:\n{output}")
    return output


def tool_version(executable: Path) -> str:
    return run_checked([str(executable), "--version"]).splitlines()[0]


def publish(
    candidate_usdz: Path,
    contract: dict[str, Any],
    raw_contract: bytes,
    source_manifest: dict[str, Any],
    source_manifest_hash: str,
    root_usdc: Path,
    member_records: list[dict[str, Any]],
) -> dict[str, Any]:
    if OUTPUT_ROOT.is_symlink():
        raise CarrierBuildError("Refusing to replace a symlinked carrier output")
    if OUTPUT_ROOT.exists():
        if OUTPUT_ROOT.parent.resolve() != GENERATED_ROOT.resolve():
            raise CarrierBuildError("Refusing to replace an unexpected output directory")
        shutil.rmtree(OUTPUT_ROOT)
    OUTPUT_ROOT.mkdir(parents=True)
    OUTPUT_USDZ.write_bytes(candidate_usdz.read_bytes())

    receipt = {
        "schemaVersion": 1,
        "carrierID": contract["carrierID"],
        "classification": contract["classification"],
        "shippingStatus": contract["shippingStatus"],
        "finalArtGate": contract["finalArtGate"],
        "domainContractImpact": "NONE",
        "sourceLibraryID": source_manifest["libraryID"],
        "sourceManifestSHA256": source_manifest_hash,
        "carrierContractSHA256": sha256_bytes(raw_contract),
        "buildToolSHA256": sha256_file(Path(__file__).resolve()),
        "realityKitVerifierSHA256": sha256_file(REALITYKIT_VERIFIER),
        "sourceUSDASHA256": sha256_file(SOURCE_USDA),
        "rootUSDCSHA256": sha256_file(root_usdc),
        "artifact": {
            "path": OUTPUT_USDZ.name,
            "byteCount": OUTPUT_USDZ.stat().st_size,
            "sha256": sha256_file(OUTPUT_USDZ),
            "memberCount": len(member_records),
            "members": member_records,
        },
        "stableMaterialPrimPaths": sorted(EXPECTED_MATERIAL_PRIMS),
        "authoredNeutralCloth": {
            "linearRGB": [0.42, 0.31, 0.2],
            "sourceBaseColorPackaged": False,
        },
        "reproducibility": {
            "independentUSDCBuildsCompared": 2,
            "independentUSDZBuildsCompared": 2,
            "byteIdentical": True,
            "fixedZipTimestampUTC": "1980-01-01T00:00:00Z",
            "payloadAlignmentBytes": 64,
        },
        "validation": {
            "usdcheckerArkitStrict": "PASS",
            "realityKitOfflineImport": "PASS",
            "relativePackagedTextures": "PASS",
            "rights": "PASS_CC0",
        },
        "toolchain": {
            "usdcat": tool_version(USDCAT),
            "usdchecker": tool_version(USDCHECKER),
            "swiftRealityKitVerifier": "xcrun swift",
        },
    }
    OUTPUT_RECEIPT.write_bytes(canonical_json_bytes(receipt))
    sums = [
        f"{sha256_file(OUTPUT_USDZ)}  {OUTPUT_USDZ.name}",
        f"{sha256_file(OUTPUT_RECEIPT)}  {OUTPUT_RECEIPT.name}",
    ]
    OUTPUT_SUMS.write_text("\n".join(sums) + "\n", encoding="utf-8")
    return receipt


def build() -> dict[str, Any]:
    contract, raw_contract = load_contract()
    source_manifest, _ = verify_source_library(contract)
    source_manifest_hash = sha256_file(source_library.MANIFEST_PATH)
    validate_usda_source(contract)

    with tempfile.TemporaryDirectory(
        prefix="chapter01-material-carrier-", dir=ROOT
    ) as temporary_directory:
        temporary_root = Path(temporary_directory)
        usdc_a, usdz_a = build_once(temporary_root / "candidate-a", contract)
        usdc_b, usdz_b = build_once(temporary_root / "candidate-b", contract)
        if usdc_a.read_bytes() != usdc_b.read_bytes():
            raise CarrierBuildError("Two independent USDC builds were not byte-identical")
        if usdz_a.read_bytes() != usdz_b.read_bytes():
            raise CarrierBuildError("Two independent USDZ builds were not byte-identical")

        verify_arkit(usdz_a)
        verify_realitykit(usdz_a)
        member_records = verify_usdz_structure(usdz_a, contract)
        receipt = publish(
            usdz_a,
            contract,
            raw_contract,
            source_manifest,
            source_manifest_hash,
            usdc_a,
            member_records,
        )

    verify_generated()
    return receipt


def verify_generated() -> None:
    contract, raw_contract = load_contract()
    source_manifest, _ = verify_source_library(contract)
    validate_usda_source(contract)
    try:
        receipt = json.loads(OUTPUT_RECEIPT.read_bytes())
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise CarrierBuildError(f"Carrier build receipt is unavailable: {error}") from error
    if receipt.get("carrierID") != contract["carrierID"]:
        raise CarrierBuildError("Generated carrier ID does not match the contract")
    if receipt.get("carrierContractSHA256") != sha256_bytes(raw_contract):
        raise CarrierBuildError("Generated carrier contract hash is stale")
    if receipt.get("buildToolSHA256") != sha256_file(Path(__file__).resolve()):
        raise CarrierBuildError("Generated carrier build-tool hash is stale")
    if receipt.get("realityKitVerifierSHA256") != sha256_file(REALITYKIT_VERIFIER):
        raise CarrierBuildError("Generated RealityKit verifier hash is stale")
    if receipt.get("sourceManifestSHA256") != sha256_file(source_library.MANIFEST_PATH):
        raise CarrierBuildError("Generated carrier source manifest hash is stale")
    if receipt.get("sourceLibraryID") != source_manifest["libraryID"]:
        raise CarrierBuildError("Generated carrier source library ID changed")
    if sha256_file(OUTPUT_USDZ) != receipt["artifact"]["sha256"]:
        raise CarrierBuildError("Generated carrier USDZ hash does not match its receipt")
    if OUTPUT_USDZ.stat().st_size != receipt["artifact"]["byteCount"]:
        raise CarrierBuildError("Generated carrier USDZ byte count does not match its receipt")
    member_records = verify_usdz_structure(OUTPUT_USDZ, contract)
    if member_records != receipt["artifact"]["members"]:
        raise CarrierBuildError("Generated carrier member inventory changed")
    if receipt.get("finalArtGate") != "OPEN":
        raise CarrierBuildError("Generated carrier incorrectly closed the final art gate")
    if receipt.get("domainContractImpact") != "NONE":
        raise CarrierBuildError("Generated carrier changed the domain contract")
    verify_arkit(OUTPUT_USDZ)
    verify_realitykit(OUTPUT_USDZ)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verify-generated",
        action="store_true",
        help="Verify the existing carrier without rebuilding it.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.verify_generated:
            verify_generated()
            print(f"PASS generated material carrier: {OUTPUT_USDZ}")
        else:
            receipt = build()
            print(
                "PASS "
                f"{receipt['carrierID']}: "
                f"{len(receipt['stableMaterialPrimPaths'])} materials, "
                f"USDZ sha256 {receipt['artifact']['sha256']}"
            )
        return 0
    except (
        CarrierBuildError,
        source_library.BuildError,
        OSError,
        KeyError,
        TypeError,
        ValueError,
        zipfile.BadZipFile,
    ) as error:
        print(f"FAIL: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
