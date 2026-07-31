#!/usr/bin/env python3
"""Primary-source-only candidate gate after the stopped V10 comparison.

The online command retrieves small publisher documents and model-repository
metadata only.  It never resolves a weight, voice or audio URL, installs a
runtime or synthesises speech.  The offline command validates the durable gate
without using the network.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, Callable
import urllib.request


SCRIPT_PATH = Path(__file__).absolute()
NARRATION_ROOT = SCRIPT_PATH.parent
REPOSITORY_ROOT = NARRATION_ROOT.parents[2]
GATE_PATH = NARRATION_ROOT / "v11-narration-candidate-gate.json"

STATUS = "CODEX_V11_PRIMARY_SOURCE_CANDIDATE_GATE_PASSED"
TRUST_DOMAIN = "CODEX_V8_DIAGNOSTIC_NON_SHIPPING"
RECORDED_AT = "2026-07-25"


class GateError(RuntimeError):
    """Raised when primary-source evidence or the durable gate drifts."""


DOCUMENTS: tuple[dict[str, Any], ...] = (
    {
        "documentID": "kokoro-code-licence",
        "candidateID": "kokoro-82m",
        "url": (
            "https://raw.githubusercontent.com/hexgrad/kokoro/"
            "dfb907a02bba8152ca444717ca5d78747ccb4bec/LICENSE"
        ),
        "bytes": 11357,
        "sha256": "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
        "requiredPhrases": ["Apache License", "Version 2.0"],
    },
    {
        "documentID": "kokoro-code-readme",
        "candidateID": "kokoro-82m",
        "url": (
            "https://raw.githubusercontent.com/hexgrad/kokoro/"
            "dfb907a02bba8152ca444717ca5d78747ccb4bec/README.md"
        ),
        "bytes": 8355,
        "sha256": "b50b84220668f8247a2405b249c34c7083acc24114279ff1429fd79f46a2c04b",
        "requiredPhrases": [
            "voice='af_heart'",
            "speed=1",
            "MacOS Apple Silicon GPU Acceleration",
        ],
    },
    {
        "documentID": "kokoro-model-readme",
        "candidateID": "kokoro-82m",
        "url": (
            "https://huggingface.co/hexgrad/Kokoro-82M/resolve/"
            "f3ff3571791e39611d31c381e3a41a3af07b4987/README.md"
        ),
        "bytes": 6348,
        "sha256": "91dcabced89db6f109b8786642f50402d3ee87450e8189589b6f85520e7f4d78",
        "requiredPhrases": [
            "license: apache-2.0",
            "Few hundred hrs",
            "permissive/non-copyrighted audio data",
        ],
    },
    {
        "documentID": "parler-code-licence",
        "candidateID": "parler-tts-mini-v1",
        "url": (
            "https://raw.githubusercontent.com/huggingface/parler-tts/"
            "d108732cd57788ec86bc857d99a6cabd66663d68/LICENSE"
        ),
        "bytes": 11359,
        "sha256": "5ee13882fce0975f0ad3c3d5c2042af4896c2a669be2d6df5b3d256811267c85",
        "requiredPhrases": ["Apache License", "Version 2.0"],
    },
    {
        "documentID": "parler-code-readme",
        "candidateID": "parler-tts-mini-v1",
        "url": (
            "https://raw.githubusercontent.com/huggingface/parler-tts/"
            "d108732cd57788ec86bc857d99a6cabd66663d68/README.md"
        ),
        "bytes": 9645,
        "sha256": "9fbf192af31078bb58a0bbf980586ee837fc58639c9ac60fba8e94c1eb475b69",
        "requiredPhrases": [
            "trained on 34 speakers",
            "speaking rate, pitch and reverberation",
            "Apple Silicon users",
        ],
    },
    {
        "documentID": "parler-model-readme",
        "candidateID": "parler-tts-mini-v1",
        "url": (
            "https://huggingface.co/parler-tts/parler-tts-mini-v1/resolve/"
            "0392b9451a601e528fd863bbb0598431fee810d9/README.md"
        ),
        "bytes": 6677,
        "sha256": "c5fdea7e1d315372c681be0e6b156d23f359f3b0c999ff8badd2b3953863b829",
        "requiredPhrases": [
            "license: apache-2.0",
            "trained on 45K hours of audio data",
            "34 speakers, characterized by name",
        ],
    },
    {
        "documentID": "styletts2-code-licence",
        "candidateID": "styletts2-libritts",
        "url": (
            "https://raw.githubusercontent.com/yl4579/StyleTTS2/"
            "5cedc71c333f8d8b8551ca59378bdcc7af4c9529/LICENSE"
        ),
        "bytes": 1075,
        "sha256": "7f023c12a1d6b25583506f6fc77f5287c7c71b65c0f886922f14153bcc07dfa9",
        "requiredPhrases": ["MIT License", "Permission is hereby granted"],
    },
    {
        "documentID": "styletts2-code-readme",
        "candidateID": "styletts2-libritts",
        "url": (
            "https://raw.githubusercontent.com/yl4579/StyleTTS2/"
            "5cedc71c333f8d8b8551ca59378bdcc7af4c9529/README.md"
        ),
        "bytes": 14167,
        "sha256": "315453e3ec0ec5b5dc2cd63b83398c317225f90e1d3c6d95777dc68446071003",
        "requiredPhrases": [
            "zero-shot speaker adaptation",
            "inference depends on a GPL-licensed package",
            "Before using these pre-trained models",
        ],
    },
    {
        "documentID": "pocket-tts-code-licence",
        "candidateID": "pocket-tts",
        "url": (
            "https://raw.githubusercontent.com/kyutai-labs/pocket-tts/"
            "058886528d0b6f2f2d4022de2e244a5260729e6e/LICENSE"
        ),
        "bytes": 1023,
        "sha256": "23f18e03dc49df91622fe2a76176497404e46ced8a715d9d2b67a7446571cca3",
        "requiredPhrases": ["Permission is hereby granted", "sell copies"],
    },
    {
        "documentID": "pocket-tts-code-readme",
        "candidateID": "pocket-tts",
        "url": (
            "https://raw.githubusercontent.com/kyutai-labs/pocket-tts/"
            "058886528d0b6f2f2d4022de2e244a5260729e6e/README.md"
        ),
        "bytes": 15528,
        "sha256": "7ae8fb6fca5961aefcc8e3d651cf8f80503fcbc00189ae92cb8bdf27155dcebb",
        "requiredPhrases": [
            "~6x real-time on a CPU of MacBook Air M4",
            "plain wav file as input for voice cloning",
            "Adding silence in the text input to generate pauses",
        ],
    },
    {
        "documentID": "pocket-tts-model-readme",
        "candidateID": "pocket-tts",
        "url": (
            "https://huggingface.co/kyutai/pocket-tts/resolve/"
            "4c8ad48f8a003909bc4f1122cbe88a4252124621/README.md"
        ),
        "bytes": 11187,
        "sha256": "ae2ebac6f8039d761ca90e2b742136dce9d7872ec8dd2105e3b2de1e3021e3aa",
        "requiredPhrases": [
            "license: cc-by-4.0",
            "extra_gated_prompt",
            "plain wav file as input for voice cloning",
        ],
    },
    {
        "documentID": "voxcpm2-code-licence",
        "candidateID": "voxcpm2",
        "url": (
            "https://raw.githubusercontent.com/OpenBMB/VoxCPM/"
            "19b6bf7590025418821a86dcb817504e0ad7e5df/LICENSE"
        ),
        "bytes": 11298,
        "sha256": "4f10acc209addacfad28293315c74c4cd648f771ee1263a748f1781d1e0265e4",
        "requiredPhrases": ["Apache License", "Version 2.0"],
    },
    {
        "documentID": "voxcpm2-code-readme",
        "candidateID": "voxcpm2",
        "url": (
            "https://raw.githubusercontent.com/OpenBMB/VoxCPM/"
            "19b6bf7590025418821a86dcb817504e0ad7e5df/README.md"
        ),
        "bytes": 28815,
        "sha256": "3baf789669d46aa706ca2f2e7056182dc0756f71a7af3c438978a9297ea2cb4e",
        "requiredPhrases": [
            "Controllable Cloning",
            "reference audio and its transcript",
            "style guidance to steer emotion, pace, and expression",
            "try to generate 1~3 times",
        ],
    },
    {
        "documentID": "voxcpm2-core-api",
        "candidateID": "voxcpm2",
        "url": (
            "https://raw.githubusercontent.com/OpenBMB/VoxCPM/"
            "19b6bf7590025418821a86dcb817504e0ad7e5df/src/voxcpm/core.py"
        ),
        "bytes": 15544,
        "sha256": "aa8965af33ebbbc611b2bad18c67b99cfffac7b7b87900f49efa8d454f2755d2",
        "requiredPhrases": [
            "reference_wav_path: str = None",
            "retry_badcase: bool = True",
            "explicit value such as ``\"cpu\"``, ``\"mps\"``",
        ],
    },
    {
        "documentID": "voxcpm2-pyproject",
        "candidateID": "voxcpm2",
        "url": (
            "https://raw.githubusercontent.com/OpenBMB/VoxCPM/"
            "19b6bf7590025418821a86dcb817504e0ad7e5df/pyproject.toml"
        ),
        "bytes": 2100,
        "sha256": "4ee48db6243be2a2eedff52843f5573c4d82179a7d47483d595889cdfc564b0d",
        "requiredPhrases": [
            'requires-python = ">=3.10"',
            'license = "Apache-2.0"',
        ],
    },
    {
        "documentID": "voxcpm2-model-readme",
        "candidateID": "voxcpm2",
        "url": (
            "https://huggingface.co/openbmb/VoxCPM2/resolve/"
            "bffb3df5a29440629464e5e839f4d214c8714c3d/README.md"
        ),
        "bytes": 7776,
        "sha256": "7384fad93ce2d98f47d5c3170597f3b31d414c12c92e7fdf3121fa90f19fe29d",
        "requiredPhrases": [
            "license: apache-2.0",
            "trained on over **2 million hours**",
            "48kHz Studio-Quality Output",
            "free for commercial use",
        ],
    },
)


MODEL_SPECS: dict[str, dict[str, Any]] = {
    "kokoro-82m": {
        "modelID": "hexgrad/Kokoro-82M",
        "revision": "f3ff3571791e39611d31c381e3a41a3af07b4987",
        "gated": False,
        "licence": "apache-2.0",
        "apiURL": (
            "https://huggingface.co/api/models/hexgrad/Kokoro-82M/revision/"
            "f3ff3571791e39611d31c381e3a41a3af07b4987?blobs=true"
        ),
        "selectedFiles": {
            "README.md": (6348, "d6dc124205ad567631d14cd8700f1af77a861c3f", None),
            "config.json": (2351, "14a726edd3718279eac426630879ff743955b16a", None),
            "kokoro-v1_0.pth": (
                327212226,
                "15769c415594dcb424579ba3dfae3085578aac4e",
                "496dba118d1a58f5f3db2efc88dbdc216e0483fc89fe6e47ee1f2c53f18ad1e4",
            ),
        },
    },
    "parler-tts-mini-v1": {
        "modelID": "parler-tts/parler-tts-mini-v1",
        "revision": "0392b9451a601e528fd863bbb0598431fee810d9",
        "gated": False,
        "licence": "apache-2.0",
        "apiURL": (
            "https://huggingface.co/api/models/parler-tts/parler-tts-mini-v1/"
            "revision/0392b9451a601e528fd863bbb0598431fee810d9?blobs=true"
        ),
        "selectedFiles": {
            "README.md": (6677, "eb45766ffa1fbc2ec21b2ee1ca795e150e9be8fe", None),
            "config.json": (6930, "d2f9d789ac92fdb73b5be24635fdffb959343389", None),
            "model.safetensors": (
                3511490560,
                "bc401b9ecf0a270858907f59f4da295b6e0bad72",
                "bc430eb6752b96ffb3f67036d1a6e207fbd031575a775716ffa64ef1eeb03692",
            ),
            "spiece.model": (
                791656,
                "317a5ccbde45300f5d1d970d4d449af2108b147e",
                "d60acb128cf7b7f2536e8f38a5b18a05535c9e14c7a355904270e15b0945ea86",
            ),
            "tokenizer.json": (2422234, "41a5ffa2657f77be129f7d2f791e45aab6c145ae", None),
        },
    },
    "styletts2-libritts": {
        "modelID": "yl4579/StyleTTS2-LibriTTS",
        "revision": "3aa7ba7f8f275ec13dce21682a61494c35089e2a",
        "gated": False,
        "licence": None,
        "apiURL": (
            "https://huggingface.co/api/models/yl4579/StyleTTS2-LibriTTS/"
            "revision/3aa7ba7f8f275ec13dce21682a61494c35089e2a?blobs=true"
        ),
        "selectedFiles": {
            "Models/LibriTTS/config.yml": (
                1859,
                "6a382d987b7a40467d0ef3d34f8c619f6ae37c3c",
                None,
            ),
            "Models/LibriTTS/epochs_2nd_00020.pth": (
                771390526,
                "b1508d92da82e15837d59ff8c2c9d63b591dd61e",
                "1164ffe19a17449d2c722234cecaf2836b35a698fb8ffd42562d2663657dca0a",
            ),
            "reference_audio.zip": (
                2917622,
                "d018bfe5d6632ec2a819926106bd93e081b0688a",
                "d25b4950ec39cec5a00f5061491ad0b3606edc6618a54adc59663bfd6e6ab55e",
            ),
        },
    },
    "pocket-tts": {
        "modelID": "kyutai/pocket-tts",
        "revision": "4c8ad48f8a003909bc4f1122cbe88a4252124621",
        "gated": "auto",
        "licence": "cc-by-4.0",
        "apiURL": (
            "https://huggingface.co/api/models/kyutai/pocket-tts/revision/"
            "4c8ad48f8a003909bc4f1122cbe88a4252124621?blobs=true"
        ),
        "selectedFiles": {
            "README.md": (11187, "0e9ad24dcd5b6fe6283cb819dd968f8f0da2bd3b", None),
            "tokenizer.model": (
                59339,
                "1820a7cbb15efc6a33dd365113c07e3df9d28d80",
                "d461765ae179566678c93091c5fa6f2984c31bbe990bf1aa62d92c64d91bc3f6",
            ),
            "tts_b6369a24.safetensors": (
                235738732,
                "3b2bcb31f77fafd57cd4951d2b61088f81a3625b",
                "a4246e239af0f35a1c495b6d180961a6f10b379dc24dd537f64c695c08e4e216",
            ),
        },
    },
    "voxcpm2": {
        "modelID": "openbmb/VoxCPM2",
        "revision": "bffb3df5a29440629464e5e839f4d214c8714c3d",
        "gated": False,
        "licence": "apache-2.0",
        "apiURL": (
            "https://huggingface.co/api/models/openbmb/VoxCPM2/revision/"
            "bffb3df5a29440629464e5e839f4d214c8714c3d?blobs=true"
        ),
        "selectedFiles": {
            "README.md": (7776, "6cb95d998835257df3e35094395b696842024163", None),
            "audiovae.pth": (
                376951122,
                "036ef0b5ced85736b842e31d35bd39606845d830",
                "94b5d51e107e0507d4acc976cfdadb64edd6fd06d1f751dadbf2fd1594274bf1",
            ),
            "config.json": (4336, "792f1c223ed607f9e508c0a0deb15dd9532483be", None),
            "model.safetensors": (
                4580080592,
                "d53929032ba7405f13a6236df11cd12da17d995a",
                "f7f964cfa9da23653baec6e6f7750719977ad944ed9f95fe52fe3a620506891d",
            ),
            "special_tokens_map.json": (
                1632,
                "8619dda6f3eb6d60d0a1bb274820054e46f41699",
                None,
            ),
            "tokenization_voxcpm2.py": (
                2895,
                "e7d768677298d058fa6ef8b160e3ca4430997fad",
                None,
            ),
            "tokenizer.json": (3676772, "41a5c2a8dba4058dd1ad73fb898abf5e4f64f0f9", None),
            "tokenizer_config.json": (
                5059,
                "fecf4cdae73b57053cac2ad34c67febbe4e4f08b",
                None,
            ),
        },
    },
}


VOX_RELEASE_URL = "https://api.github.com/repos/OpenBMB/VoxCPM/releases/tags/2.0.3"
VOX_RELEASE_EXPECTED = {
    "html_url": "https://github.com/OpenBMB/VoxCPM/releases/tag/2.0.3",
    "tag_name": "2.0.3",
    "name": "v2.0.3: fine-tuning validation, runtime stability, and streaming improvements",
    "published_at": "2026-05-11T11:59:20Z",
    "requiredBodyPhrases": [
        "Supports `auto`, `cpu`, `mps`, `cuda`",
        "Fix MPS audio quality issues by promoting low-precision dtypes to `float32`",
    ],
}

VOX_PROVENANCE_COMMENTS_URL = (
    "https://api.github.com/repos/OpenBMB/VoxCPM/issues/238/comments"
)
VOX_PROVENANCE_COMMENT_EXPECTED = {
    "html_url": "https://github.com/OpenBMB/VoxCPM/issues/238#issuecomment-4228356331",
    "created_at": "2026-04-11T06:36:43Z",
    "updated_at": "2026-04-11T06:36:43Z",
    "user": "a710128",
    "author_association": "CONTRIBUTOR",
    "requiredBodyPhrases": [
        "unable to disclose the specific details of the dataset",
        "Our model is free and open-source",
        "obtain lawful authorization for any reference audio",
    ],
}


FROZEN_THRESHOLDS = {
    "minimumUtteranceIdentityCosine": 0.98,
    "maximumAggregateWordErrorRate": 0.03,
    "maximumModelRetainedSilenceFraction": 0.1,
    "maximumRepresentativeMontageSilenceFraction": 0.115,
    "minimumProjectedFullDurationSeconds": 1080,
    "maximumProjectedFullDurationSeconds": 1320,
}

FROZEN_REFERENCES = [
    {
        "candidateID": "voice-candidate-05",
        "path": (
            "native/audio/narration/work/cast-v1-2026-07-24/references/"
            "voice-candidate-05-reference.wav"
        ),
        "bytes": 2119782,
        "sha256": "a832c5fd5ac65d5b7392f69a93f14ed0b1dfbb3ba88bb7b2d34328b215acab04",
        "durationSeconds": 14.72,
        "sampleRate": 48000,
        "channels": 1,
        "bitsPerSample": 24,
    },
    {
        "candidateID": "voice-candidate-06",
        "path": (
            "native/audio/narration/work/cast-v1-2026-07-24/references/"
            "voice-candidate-06-reference.wav"
        ),
        "bytes": 2165862,
        "sha256": "2301a67a760681c64952123683ba61283a622c00fb991b62460563b605e68386",
        "durationSeconds": 15.04,
        "sampleRate": 48000,
        "channels": 1,
        "bitsPerSample": 24,
    },
]


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "The-Long-West-V11-primary-source-gate/1",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def _load_json_bytes(data: bytes, label: str) -> Any:
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GateError(f"invalid primary JSON: {label}") from error


def _document_records(fetcher: Callable[[str], bytes]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    forbidden_suffixes = (".pth", ".pt", ".safetensors", ".wav", ".zip")
    for spec in DOCUMENTS:
        if spec["url"].lower().split("?", 1)[0].endswith(forbidden_suffixes):
            raise GateError("V11 document whitelist contains a model or audio URL")
        data = fetcher(spec["url"])
        if len(data) != spec["bytes"] or _sha256_bytes(data) != spec["sha256"]:
            raise GateError(f"primary document drifted: {spec['documentID']}")
        text = data.decode("utf-8")
        for phrase in spec["requiredPhrases"]:
            if phrase not in text:
                raise GateError(
                    f"required primary phrase missing: {spec['documentID']}: {phrase}"
                )
        records.append(dict(spec))
    return records


def _file_record(item: dict[str, Any]) -> dict[str, Any]:
    lfs = item.get("lfs") or {}
    return {
        "path": item.get("rfilename"),
        "bytes": item.get("size"),
        "blobID": item.get("blobId"),
        "sha256": lfs.get("sha256"),
    }


def _model_records(fetcher: Callable[[str], bytes]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for candidate_id, spec in MODEL_SPECS.items():
        payload = _load_json_bytes(fetcher(spec["apiURL"]), candidate_id)
        if (
            payload.get("id") != spec["modelID"]
            or payload.get("sha") != spec["revision"]
            or payload.get("gated") != spec["gated"]
            or (payload.get("cardData") or {}).get("license") != spec["licence"]
        ):
            raise GateError(f"model identity, gate or licence drifted: {candidate_id}")
        siblings = {item.get("rfilename"): item for item in payload.get("siblings", [])}
        selected: list[dict[str, Any]] = []
        for path, (size, blob_id, sha256) in spec["selectedFiles"].items():
            if path not in siblings:
                raise GateError(f"model file disappeared: {candidate_id}: {path}")
            observed = _file_record(siblings[path])
            expected = {
                "path": path,
                "bytes": size,
                "blobID": blob_id,
                "sha256": sha256,
            }
            if observed != expected:
                raise GateError(f"model file metadata drifted: {candidate_id}: {path}")
            selected.append(expected)
        records.append(
            {
                "candidateID": candidate_id,
                "modelID": spec["modelID"],
                "revision": spec["revision"],
                "gated": spec["gated"],
                "licence": spec["licence"],
                "apiURL": spec["apiURL"],
                "selectedFileCount": len(selected),
                "selectedFileBytes": sum(item["bytes"] for item in selected),
                "selectedFiles": selected,
            }
        )
    return records


def _release_record(fetcher: Callable[[str], bytes]) -> dict[str, Any]:
    payload = _load_json_bytes(fetcher(VOX_RELEASE_URL), "VoxCPM release 2.0.3")
    for field in ("html_url", "tag_name", "name", "published_at"):
        if payload.get(field) != VOX_RELEASE_EXPECTED[field]:
            raise GateError(f"VoxCPM release record drifted: {field}")
    body = payload.get("body") or ""
    for phrase in VOX_RELEASE_EXPECTED["requiredBodyPhrases"]:
        if phrase not in body:
            raise GateError(f"VoxCPM release capability disappeared: {phrase}")
    return {
        "url": VOX_RELEASE_URL,
        **VOX_RELEASE_EXPECTED,
    }


def _provenance_record(fetcher: Callable[[str], bytes]) -> dict[str, Any]:
    payload = _load_json_bytes(
        fetcher(VOX_PROVENANCE_COMMENTS_URL), "VoxCPM provenance comments"
    )
    expected_url = VOX_PROVENANCE_COMMENT_EXPECTED["html_url"]
    matches = [item for item in payload if item.get("html_url") == expected_url]
    if len(matches) != 1:
        raise GateError("VoxCPM publisher provenance comment disappeared")
    item = matches[0]
    observed_user = (item.get("user") or {}).get("login")
    for field in ("html_url", "created_at", "updated_at", "author_association"):
        if item.get(field) != VOX_PROVENANCE_COMMENT_EXPECTED[field]:
            raise GateError(f"VoxCPM provenance record drifted: {field}")
    if observed_user != VOX_PROVENANCE_COMMENT_EXPECTED["user"]:
        raise GateError("VoxCPM provenance publisher identity drifted")
    body = item.get("body") or ""
    for phrase in VOX_PROVENANCE_COMMENT_EXPECTED["requiredBodyPhrases"]:
        if phrase not in body:
            raise GateError(f"VoxCPM provenance finding disappeared: {phrase}")
    return {
        "url": VOX_PROVENANCE_COMMENTS_URL,
        **VOX_PROVENANCE_COMMENT_EXPECTED,
    }


def _candidate_records() -> list[dict[str, Any]]:
    return [
        {
            "candidateID": "kokoro-82m",
            "publisher": "hexgrad",
            "codeRevision": "dfb907a02bba8152ca444717ca5d78747ccb4bec",
            "modelRevision": "f3ff3571791e39611d31c381e3a41a3af07b4987",
            "qualityEvidence": "Publisher claims an 82M model comparable to larger systems; no project audio has been generated.",
            "control": {
                "arbitraryReferenceWavConditioning": False,
                "exactFrozenReferencePairUsable": False,
                "numericSpeedControl": True,
                "authoredBoundaryAssemblyCompatible": True,
            },
            "macFeasibility": {
                "firstPartyMacPath": True,
                "runtime": "PyTorch CPU or MPS fallback",
                "modelWeightBytes": 327212226,
            },
            "provenance": {
                "trainingScale": "few hundred hours",
                "namedCorpusDisclosure": "partial",
                "publisherStatesPermissiveOrNonCopyrightedData": True,
            },
            "licence": {
                "code": "Apache-2.0",
                "weights": "Apache-2.0",
                "commercialUsePublished": True,
            },
            "cost": {"incrementalCostNOK": 0, "billingCredentialRequired": False},
            "gate": {
                "eligibleForExactByteRuntimePreflight": False,
                "blockingReasons": ["NO_EXACT_FROZEN_REFERENCE_CONDITIONING"],
            },
        },
        {
            "candidateID": "parler-tts-mini-v1",
            "publisher": "Hugging Face",
            "codeRevision": "d108732cd57788ec86bc857d99a6cabd66663d68",
            "modelRevision": "0392b9451a601e528fd863bbb0598431fee810d9",
            "qualityEvidence": "Publisher describes an 880M model trained on 45K audiobook hours; no project audio has been generated.",
            "control": {
                "arbitraryReferenceWavConditioning": False,
                "exactFrozenReferencePairUsable": False,
                "naturalLanguagePacePitchAndRecordingControl": True,
                "namedTrainingSpeakerCount": 34,
            },
            "macFeasibility": {
                "firstPartyMacPath": True,
                "runtime": "PyTorch CPU with publisher Apple-Silicon instructions",
                "modelWeightBytes": 3511490560,
            },
            "provenance": {
                "trainingScale": "45K hours",
                "publisherStatesDatasetsAndTrainingRecipePublic": True,
                "namedCorpusDisclosure": "public linked datasets",
            },
            "licence": {
                "code": "Apache-2.0",
                "weights": "Apache-2.0",
                "commercialUsePublished": True,
            },
            "cost": {"incrementalCostNOK": 0, "billingCredentialRequired": False},
            "gate": {
                "eligibleForExactByteRuntimePreflight": False,
                "blockingReasons": ["NO_EXACT_FROZEN_REFERENCE_CONDITIONING"],
            },
        },
        {
            "candidateID": "styletts2-libritts",
            "publisher": "yl4579",
            "codeRevision": "5cedc71c333f8d8b8551ca59378bdcc7af4c9529",
            "modelRevision": "3aa7ba7f8f275ec13dce21682a61494c35089e2a",
            "qualityEvidence": "The publisher reports strong zero-shot adaptation on LibriTTS; no project audio has been generated.",
            "control": {
                "arbitraryReferenceWavConditioning": True,
                "exactFrozenReferencePairUsable": True,
                "zeroShotSpeakerAdaptation": True,
                "officialImportableInferencePathComplete": False,
            },
            "macFeasibility": {
                "firstPartyMacPath": "CPU is recommended for one artefact class",
                "runtime": "Official README points to a separate GPL inference fork or lower-quality MIT phonemizer path",
                "modelWeightBytes": 771390526,
            },
            "provenance": {
                "trainingCorpus": "LibriTTS",
                "auxiliaryModelProvenanceRequiresSeparateClosure": True,
            },
            "licence": {
                "code": "MIT",
                "weights": None,
                "commercialUsePublished": False,
                "modelRepositoryHasLicenceMetadata": False,
            },
            "cost": {"incrementalCostNOK": 0, "billingCredentialRequired": False},
            "gate": {
                "eligibleForExactByteRuntimePreflight": False,
                "blockingReasons": [
                    "OFFICIAL_WEIGHT_LICENCE_ABSENT",
                    "OFFICIAL_INFERENCE_PATH_NOT_SELF_CONTAINED",
                ],
            },
        },
        {
            "candidateID": "pocket-tts",
            "publisher": "Kyutai",
            "codeRevision": "058886528d0b6f2f2d4022de2e244a5260729e6e",
            "modelRevision": "4c8ad48f8a003909bc4f1122cbe88a4252124621",
            "qualityEvidence": "Publisher presents a 100M CPU model with voice cloning; no project audio has been generated.",
            "control": {
                "arbitraryReferenceWavConditioning": True,
                "exactFrozenReferencePairUsable": True,
                "nativePaceControl": False,
                "inlineAuthoredPauseControl": False,
                "authoredBoundaryAssemblyCompatible": True,
            },
            "macFeasibility": {
                "firstPartyMacPath": True,
                "runtime": "PyTorch CPU",
                "publisherMacBookAirM4RealtimeFactor": "approximately 6x",
                "selectedEnglishModelBytes": 235809258,
            },
            "provenance": {
                "trainingCorpusNamedInModelCard": False,
                "modelAccessRequiresContactSharingAndUseDeclaration": True,
            },
            "licence": {
                "code": "MIT",
                "weights": "CC-BY-4.0 plus gated prohibited-use terms",
                "commercialUsePublished": True,
                "newUserLegalAssentRequired": True,
            },
            "cost": {"incrementalCostNOK": 0, "billingCredentialRequired": False},
            "gate": {
                "eligibleForExactByteRuntimePreflight": False,
                "blockingReasons": [
                    "NEW_USER_LEGAL_ASSENT_NOT_AUTHORIZED",
                    "NO_NATIVE_PACE_OR_INLINE_PAUSE_CONTROL",
                ],
            },
        },
        {
            "candidateID": "voxcpm2",
            "publisher": "OpenBMB",
            "codeRevision": "19b6bf7590025418821a86dcb817504e0ad7e5df",
            "modelRevision": "bffb3df5a29440629464e5e839f4d214c8714c3d",
            "qualityEvidence": "Publisher reports competitive public zero-shot and controllable-TTS benchmarks for a 2B, 48 kHz model; project quality remains untested.",
            "control": {
                "arbitraryReferenceWavConditioning": True,
                "exactFrozenReferencePairUsable": True,
                "referenceTranscriptConditioning": True,
                "paceEmotionAndExpressionGuidance": True,
                "retryCanBeExplicitlyDisabled": True,
            },
            "macFeasibility": {
                "firstPartyMacPath": True,
                "runtime": "PyTorch MPS with float32 promotion in release 2.0.3",
                "selectedModelBytes": 4960731703,
                "currentMachineClass": "Apple M5 Pro, 64 GB, arm64",
            },
            "provenance": {
                "trainingScale": "over 2 million hours",
                "specificDatasetDetailsDisclosed": False,
                "publisherReason": "trade-secret protection",
                "referenceAuthorization": "project-controlled synthetic references",
            },
            "licence": {
                "code": "Apache-2.0",
                "weights": "Apache-2.0",
                "commercialUsePublished": True,
                "modelRepositoryGated": False,
            },
            "cost": {"incrementalCostNOK": 0, "billingCredentialRequired": False},
            "gate": {
                "eligibleForExactByteRuntimePreflight": True,
                "blockingReasons": [],
                "risksCarriedIntoNextGate": [
                    "UNDISCLOSED_TRAINING_DATASET_DETAILS",
                    "PUBLISHER_RECOMMENDS_MULTIPLE_TAKES_BUT_PROJECT_PERMITS_ONE",
                    "LARGE_MPS_RUNTIME_REQUIRES_EXACT_MEMORY_AND_DEPENDENCY_PROOF",
                ],
            },
        },
    ]


def expected_gate() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "recordedAt": RECORDED_AT,
        "scope": {
            "officialPublisherSourcesOnly": True,
            "minimumCandidatesIncluded": [
                "kokoro-82m",
                "parler-tts-mini-v1",
                "styletts2-libritts",
            ],
            "additionalCandidatesIncluded": ["pocket-tts", "voxcpm2"],
            "retrievedModelOrVoiceBytes": False,
            "installedRuntime": False,
            "generatedAudio": False,
            "changedFrozenThreshold": False,
        },
        "frozenInputs": {
            "referenceTranscript": {
                "path": "native/audio/narration/identity-reference-v1.txt",
                "bytes": 202,
                "sha256": "a7ccefaf433c8998c1556ba5465c49031a8210e903d32542f8c6aa5a525cc011",
            },
            "references": FROZEN_REFERENCES,
            "representativeUtteranceCountPerReference": 14,
            "thresholds": FROZEN_THRESHOLDS,
        },
        "primaryDocuments": [dict(item) for item in DOCUMENTS],
        "modelMetadata": _expected_model_records(),
        "publisherRecords": {
            "voxcpm203Release": {"url": VOX_RELEASE_URL, **VOX_RELEASE_EXPECTED},
            "voxcpmTrainingDataAndCommercialComment": {
                "url": VOX_PROVENANCE_COMMENTS_URL,
                **VOX_PROVENANCE_COMMENT_EXPECTED,
            },
        },
        "candidates": _candidate_records(),
        "decision": {
            "selectedCandidateID": "voxcpm2",
            "selectedCandidateCount": 1,
            "nextGate": "EXACT_BYTES_MACOS_ARM64_RUNTIME_AND_LICENCES",
            "selectionReasons": [
                "DIRECT_CONDITIONING_ON_BOTH_FROZEN_REFERENCES_AND_TRANSCRIPT",
                "FIRST_PARTY_PACE_EXPRESSION_AND_TIMBRE_CONTROLS",
                "FIRST_PARTY_MPS_PATH_WITH_RECORDED_FLOAT32_FIX",
                "APACHE_2_CODE_AND_WEIGHT_LICENCES_WITHOUT_GATED_ACCESS",
                "HIGHEST_DOCUMENTED_QUALITY_CEILING_IN_THE_ELIGIBLE_SET",
            ],
            "exactByteRuntimePreflightPermitted": True,
            "modelDownloadPermittedOnlyInsideHashVerifyingNextPreflight": True,
            "comparisonSynthesisPermitted": False,
            "full203By2GenerationPermitted": False,
            "candidatePromotionPermitted": False,
            "masterParentPermitted": False,
            "shippingPermitted": False,
            "nextMethodMust": [
                "pin every source, model and runtime byte before loading",
                "use the two unchanged project references and exact transcript",
                "set retry_badcase=false and permit one attempt per utterance",
                "freeze seed, device, dtype, guidance and diffusion steps before synthesis",
                "retain every V8 identity, word, pronunciation, silence and duration threshold",
                "stop before synthesis if MPS load, dependency licence or memory proof fails",
            ],
        },
        "cost": {
            "incrementalCostNOK": 0,
            "billingCredentialUsed": False,
            "hostedSynthesisUsed": False,
            "externalHumanAdded": False,
        },
    }


def _expected_model_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for candidate_id, spec in MODEL_SPECS.items():
        files = [
            {
                "path": path,
                "bytes": size,
                "blobID": blob_id,
                "sha256": sha256,
            }
            for path, (size, blob_id, sha256) in spec["selectedFiles"].items()
        ]
        records.append(
            {
                "candidateID": candidate_id,
                "modelID": spec["modelID"],
                "revision": spec["revision"],
                "gated": spec["gated"],
                "licence": spec["licence"],
                "apiURL": spec["apiURL"],
                "selectedFileCount": len(files),
                "selectedFileBytes": sum(item["bytes"] for item in files),
                "selectedFiles": files,
            }
        )
    return records


def preflight(fetcher: Callable[[str], bytes] = _fetch) -> dict[str, Any]:
    if _document_records(fetcher) != [dict(item) for item in DOCUMENTS]:
        raise GateError("primary document record construction drifted")
    if _model_records(fetcher) != _expected_model_records():
        raise GateError("model metadata record construction drifted")
    if _release_record(fetcher) != {
        "url": VOX_RELEASE_URL,
        **VOX_RELEASE_EXPECTED,
    }:
        raise GateError("VoxCPM release finding drifted")
    if _provenance_record(fetcher) != {
        "url": VOX_PROVENANCE_COMMENTS_URL,
        **VOX_PROVENANCE_COMMENT_EXPECTED,
    }:
        raise GateError("VoxCPM provenance finding drifted")
    return expected_gate()


def validate(path: Path = GATE_PATH) -> dict[str, Any]:
    try:
        gate = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateError(f"cannot load V11 candidate gate: {path}") from error
    if gate != expected_gate():
        raise GateError("durable V11 candidate gate drifted")

    transcript = gate["frozenInputs"]["referenceTranscript"]
    transcript_path = REPOSITORY_ROOT / transcript["path"]
    if (
        not transcript_path.is_file()
        or transcript_path.stat().st_size != transcript["bytes"]
        or _sha256_path(transcript_path) != transcript["sha256"]
    ):
        raise GateError("frozen reference transcript drifted")

    local_reference_count = 0
    for record in gate["frozenInputs"]["references"]:
        reference = REPOSITORY_ROOT / record["path"]
        if reference.exists():
            local_reference_count += 1
            if (
                not reference.is_file()
                or reference.stat().st_size != record["bytes"]
                or _sha256_path(reference) != record["sha256"]
            ):
                raise GateError(f"frozen local reference drifted: {record['candidateID']}")

    selected = [
        item
        for item in gate["candidates"]
        if item["gate"]["eligibleForExactByteRuntimePreflight"]
    ]
    if [item["candidateID"] for item in selected] != ["voxcpm2"]:
        raise GateError("V11 selected eligibility set drifted")
    decision = gate["decision"]
    if (
        decision["selectedCandidateID"] != "voxcpm2"
        or decision["selectedCandidateCount"] != 1
        or decision["comparisonSynthesisPermitted"] is not False
        or decision["full203By2GenerationPermitted"] is not False
    ):
        raise GateError("V11 stopped decision drifted")
    return {
        "status": gate["status"],
        "candidateCount": len(gate["candidates"]),
        "eligibleCandidateCount": len(selected),
        "selectedCandidateID": decision["selectedCandidateID"],
        "primaryDocumentCount": len(gate["primaryDocuments"]),
        "modelMetadataRecordCount": len(gate["modelMetadata"]),
        "locallyPresentReferenceCount": local_reference_count,
        "generatedAudio": False,
        "incrementalCostNOK": 0,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    preflight_parser = subparsers.add_parser("preflight")
    preflight_parser.add_argument("--output", type=Path, default=GATE_PATH)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--gate", type=Path, default=GATE_PATH)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "preflight":
            result = preflight()
            output = args.output.absolute()
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(
                json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            summary = {
                "status": result["status"],
                "candidateCount": len(result["candidates"]),
                "selectedCandidateID": result["decision"]["selectedCandidateID"],
                "modelOrAudioBytesRetrieved": False,
                "output": str(output),
            }
        else:
            summary = validate(args.gate.absolute())
    except GateError as error:
        print(f"V11 narration candidate gate failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
