#!/usr/bin/env python3
"""Primary-source gate for an OpenVoice V2 + MeloTTS V8 comparison.

This block retrieves only small official metadata and documentation records.
It binds exact future source archives and model files, licences, known
training-data disclosures, reference ownership and the one synthesis method
that is compatible with the frozen V8 no-repair contract.  It does not
download source archives or model weights, install code or render audio.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from typing import Any, Callable
import urllib.request

import pipeline as production
import v6_pipeline as v6
import v8_pipeline as v8
import v9_local_synthesis_inventory as v9


SCRIPT_PATH = Path(__file__).absolute()
STATUS = "CODEX_V10_OPENVOICE_V2_PRIMARY_SOURCE_GATE_PASSED"
TRUST_DOMAIN = v8.TRUST_DOMAIN
RECEIPT_NAME = "openvoice-v2-primary-source-gate.v10.receipt.json"

OPENVOICE_CODE_REVISION = "74a1d147b17a8c3092dd5430504bd83ef6c7eb23"
OPENVOICE_MODEL_REVISION = "f36e7edfe1684461a8343844af60babc2efbb727"
MELO_CODE_REVISION = "209145371cff8fc3bd60d7be902ea69cbdb7965a"
MELO_MODEL_REVISION = "bb4fb7346d566d277ba8c8c7dbfdf6786139b8ef"
BERT_MODEL_REVISION = "86b5e0934494bd15c9632b12f734a8a67f723594"


PRIMARY_DOCUMENTS: dict[str, dict[str, Any]] = {
    "openVoiceCodeLicence": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/OpenVoice/"
            f"{OPENVOICE_CODE_REVISION}/LICENSE"
        ),
        "bytes": 1057,
        "sha256": "bb3541f421e6273d3a3e3dd5bdba2bd3b79a3c2eadca65cde9c62c2467903ac0",
        "requiredPhrases": ["Copyright 2024 MyShell.ai", "Permission is hereby granted"],
    },
    "openVoiceRepositoryReadme": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/OpenVoice/"
            f"{OPENVOICE_CODE_REVISION}/README.md"
        ),
        "bytes": 3120,
        "sha256": "3c6f5d24798763ebb9ca5fea8a1cbd21b935a140300ba531138b5518cd297dfc",
        "requiredPhrases": [
            "Accurate Tone Color Cloning",
            "Free Commercial Use",
            "both V2 and V1 are released under MIT License",
            "rhythm, pauses, and intonation",
        ],
    },
    "openVoiceQa": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/OpenVoice/"
            f"{OPENVOICE_CODE_REVISION}/docs/QA.md"
        ),
        "bytes": 3354,
        "sha256": "e982bf60b0351c311738e7d367666f8d8e6f7fb2d7e55cc7f988cc648a66904b",
        "requiredPhrases": [
            "OpenVoice only clones the tone color",
            "controlled by the base speaker TTS model",
        ],
    },
    "openVoiceApi": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/OpenVoice/"
            f"{OPENVOICE_CODE_REVISION}/openvoice/api.py"
        ),
        "bytes": 7823,
        "sha256": "6830abaf9b0ea6023fe7e3df3d9a0a1fd9b73a7dbbc13f8a892da009052637b9",
        "requiredPhrases": [
            "def extract_se(self, ref_wav_list",
            "def convert(self, audio_src_path, src_se, tgt_se",
            "enable_watermark",
        ],
    },
    "openVoiceV2Demo": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/OpenVoice/"
            f"{OPENVOICE_CODE_REVISION}/demo_part3.ipynb"
        ),
        "bytes": 4869,
        "sha256": "b60a930f422c0a39908142f10d769e7c7afeeea5b1010b50dda55c269cdd0843",
        "requiredPhrases": [
            "Use MeloTTS as Base Speakers",
            "Speed is adjustable",
            "base_speakers/ses/{speaker_key}.pth",
        ],
    },
    "openVoiceV2ControlIssue": {
        "url": "https://api.github.com/repos/myshell-ai/OpenVoice/issues/232",
        "canonicalJsonFields": [
            "html_url",
            "state",
            "title",
            "created_at",
            "updated_at",
            "body",
        ],
        "canonicalSHA256": "8ae481fbbf4e7d108690942fc25a152c2ad9328ee7c9dfa5c143227f10629a17",
        "requiredPhrases": [
            "v2 and emotion / precise voice control.",
            "no example of how to accomplish this in practice",
            "Is there some documentation I'm missing?",
        ],
    },
    "openVoicePaperV2": {
        "url": "https://arxiv.org/html/2312.01479v2",
        "bytes": 76896,
        "sha256": "9af5115c951e11676156a2fa95ffb638713536ab3cf16bbacdcb17614c32b770",
        "requiredPhrases": [
            "audio samples from two English speakers (American and British accents)",
            "There are 30K sentences in total",
            "300K audio samples from 20K individuals",
        ],
    },
    "openVoiceModelReadme": {
        "url": (
            "https://huggingface.co/myshell-ai/OpenVoiceV2/resolve/"
            f"{OPENVOICE_MODEL_REVISION}/README.md"
        ),
        "bytes": 5371,
        "sha256": "9f7d4211260d6105d0106705ae250c947bf3fb28e8e40a196de36a0e70d49394",
        "requiredPhrases": ["license: mit", "Free Commercial Use"],
    },
    "meloCodeLicence": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/MeloTTS/"
            f"{MELO_CODE_REVISION}/LICENSE"
        ),
        "bytes": 1053,
        "sha256": "88a50e5a02bbc2a5c2f084dc19da751aa97b1690f5fda76cd8005c8634d1ca70",
        "requiredPhrases": ["Copyright (c) 2024 MyShell.ai", "Permission is hereby granted"],
    },
    "meloApi": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/MeloTTS/"
            f"{MELO_CODE_REVISION}/melo/api.py"
        ),
        "bytes": 5108,
        "sha256": "942f773a2a90ace001108d996e645e48f338c513733f0f6667c6070e04df7a70",
        "requiredPhrases": [
            "length_scale=1. / speed",
            "audio_numpy_concat",
            "[0] * int((sr * 0.05) / speed)",
        ],
    },
    "meloEnglishBertSource": {
        "url": (
            "https://raw.githubusercontent.com/myshell-ai/MeloTTS/"
            f"{MELO_CODE_REVISION}/melo/text/english_bert.py"
        ),
        "bytes": 1194,
        "sha256": "0987c4ce65ff9aff4c1b23b25f5903a580e4c907b3d1814e2e97db6dcb020805",
        "requiredPhrases": [
            "model_id = 'bert-base-uncased'",
            "AutoModelForMaskedLM.from_pretrained(model_id)",
        ],
    },
    "meloModelReadme": {
        "url": (
            "https://huggingface.co/myshell-ai/MeloTTS-English/resolve/"
            f"{MELO_MODEL_REVISION}/README.md"
        ),
        "bytes": 5755,
        "sha256": "493958e29457067b476c3e871885d848dd46c8fb74c8694b46fa94ad062e00c1",
        "requiredPhrases": [
            "license: mit",
            "free for both commercial and non-commercial use",
            "British accent",
        ],
    },
    "bertLicence": {
        "url": (
            "https://huggingface.co/google-bert/bert-base-uncased/resolve/"
            f"{BERT_MODEL_REVISION}/LICENSE"
        ),
        "bytes": 11356,
        "sha256": "43070e2d4e532684de521b885f385d0841030efa2b1a20bafb76133a5e1379c1",
        "requiredPhrases": ["Apache License", "Version 2.0"],
    },
    "bertModelReadme": {
        "url": (
            "https://huggingface.co/google-bert/bert-base-uncased/resolve/"
            f"{BERT_MODEL_REVISION}/README.md"
        ),
        "bytes": 10517,
        "sha256": "9187b6018ea0010d884e78e098e328faa1b88b301570d0cce606bb35e4067e17",
        "requiredPhrases": ["license: apache-2.0", "BookCorpus", "English Wikipedia"],
    },
}


MODEL_SPECS: dict[str, dict[str, Any]] = {
    "openVoiceV2": {
        "modelID": "myshell-ai/OpenVoiceV2",
        "revision": OPENVOICE_MODEL_REVISION,
        "licence": "mit",
        "apiURL": (
            "https://huggingface.co/api/models/myshell-ai/OpenVoiceV2/revision/"
            f"{OPENVOICE_MODEL_REVISION}?blobs=true"
        ),
        "files": {
            "README.md": {
                "bytes": 5371,
                "blobID": "75848c485475e0d9c9c145084a2d4f85bd74cf68",
                "sha256": "9f7d4211260d6105d0106705ae250c947bf3fb28e8e40a196de36a0e70d49394",
            },
            "base_speakers/ses/en-br.pth": {
                "bytes": 1701,
                "blobID": "848b00486ea77ea4c71a7bc90b5cf126ad3e1695",
                "sha256": "2bf5a88025cfd10473b25d65d5c0e608338ce4533059c5f9a3383e69c812d389",
            },
            "converter/checkpoint.pth": {
                "bytes": 131320490,
                "blobID": "fa2f9421735901fd3db22a904f07b5a591faad7d",
                "sha256": "9652c27e92b6b2a91632590ac9962ef7ae2b712e5c5b7f4c34ec55ee2b37ab9e",
            },
            "converter/config.json": {
                "bytes": 838,
                "blobID": "3e33566b0d976167bd5f15801ef7005d59143e2f",
                "sha256": "9dfff60350b8c63f2c664efd92a61b2516efb22671466960f0e5dfebd881fa47",
            },
        },
    },
    "meloEnglish": {
        "modelID": "myshell-ai/MeloTTS-English",
        "revision": MELO_MODEL_REVISION,
        "licence": "mit",
        "apiURL": (
            "https://huggingface.co/api/models/myshell-ai/MeloTTS-English/revision/"
            f"{MELO_MODEL_REVISION}?blobs=true"
        ),
        "files": {
            "README.md": {
                "bytes": 5755,
                "blobID": "84aa61457d8d8bf8dc04da1e9236b34bd92e1b9d",
                "sha256": "493958e29457067b476c3e871885d848dd46c8fb74c8694b46fa94ad062e00c1",
            },
            "checkpoint.pth": {
                "bytes": 207860748,
                "blobID": "783f3844ca1278c135ad6c25ad9804e5a4295fa4",
                "sha256": "acd278040eaf9536908e2b965273df5a731c44d8f0da66cc5fed7972772ed23c",
            },
            "config.json": {
                "bytes": 3488,
                "blobID": "c86f50565b62f3caa07fa9ad795db1169be2253a",
                "sha256": "039116c927c70eaa4458d315ea83aaaa99e1fca1c621b50c8ca56b4a5700eb77",
            },
        },
    },
    "bertBaseUncased": {
        "modelID": "google-bert/bert-base-uncased",
        "revision": BERT_MODEL_REVISION,
        "licence": "apache-2.0",
        "apiURL": (
            "https://huggingface.co/api/models/google-bert/bert-base-uncased/revision/"
            f"{BERT_MODEL_REVISION}?blobs=true"
        ),
        "files": {
            "LICENSE": {
                "bytes": 11356,
                "blobID": "f49a4e16e68b128803cc2dcea614603632b04eac",
                "sha256": "43070e2d4e532684de521b885f385d0841030efa2b1a20bafb76133a5e1379c1",
            },
            "README.md": {
                "bytes": 10517,
                "blobID": "40a2aaca31dd005eb5f6ffad07b5ffed0a31d1f6",
                "sha256": "9187b6018ea0010d884e78e098e328faa1b88b301570d0cce606bb35e4067e17",
            },
            "config.json": {
                "bytes": 570,
                "blobID": "45a2321a7ecfdaaf60a6c1fd7f5463994cc8907d",
                "sha256": "7160e1553ad2ca51d8c1cb066be533db31826e12d173824c1bb0cb1a4f187d20",
            },
            "model.safetensors": {
                "bytes": 440449768,
                "blobID": "a090ee7d80c0e00eca57c5aaaa54d136d58c5218",
                "sha256": "68d45e234eb4a928074dfd868cead0219ab85354cc53d20e772753c6bb9169d3",
            },
            "tokenizer.json": {
                "bytes": 466062,
                "blobID": "949a6f013d67eb8a5b4b5b46026217b888021b88",
                "sha256": "ce64fce797c24f68df90b40a3f74f579b336a493db14bd583fd520ea0d8c9a98",
            },
            "tokenizer_config.json": {
                "bytes": 48,
                "blobID": "e5c73d8a50df1f56fb5b0b8002d7cf4010afdccb",
                "sha256": "a025160ef0431f1a392f6f050c1310f4c5d9fb6f275932dbccba73c4d214bf10",
            },
            "vocab.txt": {
                "bytes": 231508,
                "blobID": "fb140275c155a9c7c5a3b3e0e77a9e839594a938",
                "sha256": "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3",
            },
        },
    },
}


CODE_ARCHIVES = {
    "openVoice": {
        "revision": OPENVOICE_CODE_REVISION,
        "url": (
            "https://codeload.github.com/myshell-ai/OpenVoice/tar.gz/"
            f"{OPENVOICE_CODE_REVISION}"
        ),
        "bytes": 3193160,
        "sha256": "a0bc7e5b2968ab7f8898d237b2b36f7de46710cbc3901f97dff29781eeae8abd",
        "licence": "MIT",
    },
    "meloTTS": {
        "revision": MELO_CODE_REVISION,
        "url": (
            "https://codeload.github.com/myshell-ai/MeloTTS/tar.gz/"
            f"{MELO_CODE_REVISION}"
        ),
        "bytes": 5873911,
        "sha256": "ceb9a1a636522fee6489c8496ef5b6b9b3b8c1e8441f402eea00d8a17fbe52b8",
        "licence": "MIT",
    },
}


Fetcher = Callable[[str], bytes]


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _fetch_url(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "The-Long-West-narration-primary-source-gate/1"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def validate_primary_documents(fetcher: Fetcher = _fetch_url) -> dict[str, Any]:
    records: dict[str, Any] = {}
    for document_id, spec in PRIMARY_DOCUMENTS.items():
        payload = fetcher(spec["url"])
        current = {"bytes": len(payload), "sha256": _sha256_bytes(payload)}
        canonical_binding: dict[str, Any] = {}
        if "canonicalJsonFields" in spec:
            document = json.loads(payload.decode("utf-8"))
            canonical = {
                key: document.get(key) for key in spec["canonicalJsonFields"]
            }
            canonical_digest = _sha256_bytes(
                v8.canonical_json(canonical).encode("utf-8")
            )
            if canonical_digest != spec["canonicalSHA256"]:
                raise v8.V8Error(
                    f"primary canonical document drifted: {document_id}"
                )
            canonical_binding = {
                "canonicalJsonFields": spec["canonicalJsonFields"],
                "canonicalSHA256": canonical_digest,
            }
        elif current != {"bytes": spec["bytes"], "sha256": spec["sha256"]}:
            raise v8.V8Error(f"primary document bytes drifted: {document_id}")
        text = payload.decode("utf-8")
        absent = [phrase for phrase in spec["requiredPhrases"] if phrase not in text]
        if absent:
            raise v8.V8Error(f"primary document claim drifted: {document_id}")
        records[document_id] = {
            "url": spec["url"],
            **current,
            **canonical_binding,
            "requiredPhraseSHA256": [
                production.sha256_text(item) for item in spec["requiredPhrases"]
            ],
            "allRequiredClaimsPresent": True,
        }
    return records


def _metadata_file_record(item: dict[str, Any]) -> dict[str, Any]:
    record = {
        "bytes": item.get("size"),
        "blobID": item.get("blobId"),
    }
    lfs = item.get("lfs") or {}
    if lfs:
        record["sha256"] = lfs.get("sha256")
    return {key: value for key, value in record.items() if value is not None}


def validate_model_metadata(fetcher: Fetcher = _fetch_url) -> dict[str, Any]:
    models: dict[str, Any] = {}
    for label, spec in MODEL_SPECS.items():
        payload = json.loads(fetcher(spec["apiURL"]).decode("utf-8"))
        if (
            payload.get("id") != spec["modelID"]
            or payload.get("sha") != spec["revision"]
            or (payload.get("cardData") or {}).get("license") != spec["licence"]
        ):
            raise v8.V8Error(f"model identity or licence drifted: {label}")
        siblings = {
            item["rfilename"]: _metadata_file_record(item)
            for item in payload.get("siblings", [])
        }
        selected: list[dict[str, Any]] = []
        for name, expected in spec["files"].items():
            current = siblings.get(name)
            metadata_expected = {
                key: value
                for key, value in expected.items()
                if key != "sha256" or "sha256" in current
            }
            if current != metadata_expected:
                raise v8.V8Error(f"model file metadata drifted: {label}/{name}")
            selected.append({"path": name, **expected})
        models[label] = {
            "modelID": spec["modelID"],
            "revision": spec["revision"],
            "licence": spec["licence"],
            "apiURL": spec["apiURL"],
            "apiResponseSHA256": _sha256_bytes(
                v8.canonical_json(
                    {
                        "id": payload["id"],
                        "sha": payload["sha"],
                        "license": payload["cardData"]["license"],
                        "selectedFiles": selected,
                    }
                ).encode("utf-8")
            ),
            "selectedFiles": selected,
            "selectedFileCount": len(selected),
            "selectedDownloadBytes": sum(item["bytes"] for item in selected),
            "everySelectedFileExactlyBound": True,
        }
    return models


def download_plan() -> dict[str, Any]:
    model_bytes = sum(
        item["bytes"]
        for spec in MODEL_SPECS.values()
        for item in spec["files"].values()
    )
    code_bytes = sum(item["bytes"] for item in CODE_ARCHIVES.values())
    return {
        "codeArchives": CODE_ARCHIVES,
        "models": {
            label: {
                "modelID": spec["modelID"],
                "revision": spec["revision"],
                "selectedFiles": [
                    {"path": path, **binding}
                    for path, binding in spec["files"].items()
                ],
            }
            for label, spec in MODEL_SPECS.items()
        },
        "codeArchiveBytes": code_bytes,
        "modelAndEvidenceBytes": model_bytes,
        "totalBoundDownloadBytes": code_bytes + model_bytes,
        "totalBoundDownloadMiB": round((code_bytes + model_bytes) / 1024**2, 3),
        "unlistedFilesPermitted": False,
        "mutableRevisionAliasesPermitted": False,
        "downloadOnlyAfterThisGatePasses": True,
    }


def synthesis_method_contract() -> dict[str, Any]:
    v6_config = v6.load_config()
    v8_config = v8.load_config()
    join = v6_config["join"]
    remediation = v8_config["remediationContract"]
    _, _, _, utterances, _ = v8.segmentation_material()
    pause_counts = {30: 0, 120: 0, 0: 0}
    for utterance in utterances:
        separator = utterance["separatorAfter"]
        pause = 120 if "\n\n" in separator else (30 if separator else 0)
        pause_counts[pause] += 1
    total_pause_ms = sum(pause * count for pause, count in pause_counts.items())
    if (
        join.get("intraParagraphPauseMilliseconds") != 30
        or join.get("paragraphPauseMilliseconds") != 120
        or join.get("finalPauseMilliseconds") != 0
        or remediation.get("adaptiveZeroPaddingProhibited") is not True
        or remediation.get("durationPaddingProhibited") is not True
        or remediation.get("speechTimeStretchProhibited") is not True
        or remediation.get("activityCropOnlyAtRawOuterEdgesWithInheritedRolls")
        is not True
        or v8_config["segmentation"].get("authoredSeparatorsPreservedByteForByte")
        is not True
    ):
        raise v8.V8Error("frozen V8 pause or repair contract drifted")
    return {
        "baseSpeaker": "MeloTTS-English/EN-BR",
        "device": "cpu",
        "fixedGenerationParametersRequired": True,
        "fixedSeedRequired": True,
        "explicitLocalFilesOnly": True,
        "everyFileHashVerifiedBeforeLoading": True,
        "networkDuringRuntimePermitted": False,
        "localBertRevision": BERT_MODEL_REVISION,
        "oneExactV8UtterancePerInference": True,
        "baseModelCall": "TTS.model.infer",
        "publicTtsToFileCallPermitted": False,
        "audioNumpyConcatCallPermitted": False,
        "automaticSentenceSplitterPermitted": False,
        "publicTtsToFileProhibitionReason": (
            "MeloTTS audio_numpy_concat appends 50/speed milliseconds of "
            "non-authored zeros after every generated segment, including the last."
        ),
        "modelNativeRateControl": {
            "parameter": "speed",
            "modelArgument": "length_scale=1.0/speed",
            "postSynthesisTimeStretch": False,
        },
        "toneColourConditioning": {
            "engine": "OpenVoice V2 ToneColorConverter",
            "bothExactFrozenFinalistReferencesRequired": True,
            "referenceExtractionCall": "ToneColorConverter.extract_se",
            "standardGetSeHelperPermitted": False,
            "conversionCall": "ToneColorConverter.convert",
            "watermarkRuntimeEnabled": False,
            "convertedWaveformPostProcessingPermitted": False,
        },
        "authoredBoundaryPauses": {
            "source": "exact V8 separatorAfter values",
            "intraParagraphMilliseconds": join["intraParagraphPauseMilliseconds"],
            "paragraphMilliseconds": join["paragraphPauseMilliseconds"],
            "finalMilliseconds": join["finalPauseMilliseconds"],
            "intraParagraphBoundaryCount": pause_counts[30],
            "paragraphBoundaryCount": pause_counts[120],
            "finalBoundaryCount": pause_counts[0],
            "totalMillisecondsAcrossCompleteV8Assembly": total_pause_ms,
            "adaptive": False,
            "durationFilling": False,
            "appliedAfterUnmodifiedConverterOutput": True,
        },
        "rawGeneratedSpeechPaddingSamples": 0,
        "rawOuterActivityCropApplied": False,
        "internalSilenceRemoval": False,
        "masterSilenceTrimming": False,
        "wholeAssemblyTempoCorrection": False,
        "meetsFrozenV8NoRepairContract": True,
    }


def _licence_and_provenance_gate(references: dict[str, Any]) -> dict[str, Any]:
    return {
        "code": {
            "openVoiceMIT": True,
            "meloTTSMIT": True,
        },
        "weights": {
            "openVoiceV2MITAndCommercialUseExplicit": True,
            "meloTTSMITAndCommercialUseExplicit": True,
            "bertBaseUncasedApache2": True,
        },
        "trainingDisclosure": {
            "openVoicePaper": (
                "The official paper reports 30,000 base-speaker sentences and "
                "300,000 converter samples from 20,000 individuals. It does not "
                "name the collected corpora or publish individual voice consents."
            ),
            "meloTTSModelCard": (
                "The official English model card does not identify its training "
                "corpus or individual base-speaker voice terms."
            ),
            "bertBaseUncased": "BookCorpus and English Wikipedia are disclosed.",
            "trainingCorpusIdentityComplete": False,
            "publishedWeightUseLicencesRemainExplicit": True,
            "undisclosedTrainingDetailsRecordedAsProvenanceLimitation": True,
        },
        "projectVoiceMaterial": {
            "referenceIDs": sorted(references),
            "referenceCount": len(references),
            "allReferencesAreProjectControlledSyntheticFinalists": all(
                item["syntheticCandidateReference"] for item in references.values()
            ),
            "externalHumanVoiceContributorAddedByThisMethod": False,
            "builtInBritishBaseEmbeddingShipsUnderBoundOpenVoiceV2MITPackage": True,
        },
        "separateOutputUseRestrictionFoundInBoundPrimarySources": False,
        "commercialLicenceGatePassed": True,
        "provenanceLimitationsDoNotOverridePublishedCommercialWeightLicences": True,
    }


def preflight(args: argparse.Namespace, fetcher: Fetcher = _fetch_url) -> dict[str, Any]:
    if args.primary_source_network is not True:
        raise v8.V8Error("OpenVoice V2 preflight requires --primary-source-network")
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"

    config = v8.load_config()
    output = v8.prepare_output(args.output, config)
    dependencies = v8.validate_dependencies(config)
    comparison = v9.frozen_comparison_contract(config)
    documents = validate_primary_documents(fetcher)
    models = validate_model_metadata(fetcher)
    plan = download_plan()
    method = synthesis_method_contract()
    references = comparison["references"]
    licence = _licence_and_provenance_gate(references)

    eligibility = {
        "genuinelyDifferentFromQwenAndChatterbox": True,
        "exactOfficialCodeRevisionsBound": True,
        "exactOfficialWeightRevisionsAndFilesBound": True,
        "commercialCodeAndWeightLicencesPassed": licence[
            "commercialLicenceGatePassed"
        ],
        "trainingAndVoiceTermsRecorded": True,
        "offlineCapableAfterBoundDownload": True,
        "conditionsOnBothFrozenReferences": True,
        "modelNativeRateControl": method["modelNativeRateControl"][
            "postSynthesisTimeStretch"
        ]
        is False,
        "v8AuthoredPauseControlWithoutPaddingOrTrimming": method[
            "meetsFrozenV8NoRepairContract"
        ],
        "exactDownloadSizeBound": plan["totalBoundDownloadBytes"] > 0,
        "incrementalCostNOKIsZero": True,
    }
    if not all(eligibility.values()):
        raise v8.V8Error("OpenVoice V2 primary-source candidate gate failed")

    receipt = {
        "schemaVersion": 1,
        "status": STATUS,
        "trustDomain": TRUST_DOMAIN,
        "createdAt": production.timestamp(),
        "script": v8.file_binding(SCRIPT_PATH),
        "v8Pipeline": v8.file_binding(v8.SCRIPT_PATH),
        "v8Config": v8.file_binding(v8.CONFIG_PATH),
        "v8ValidatedDependencies": dependencies,
        "localInventoryReceipt": v8.file_binding(
            v8.repository_path(
                "native/audio/narration/work/provisional-audit-v8/"
                "local-synthesis-inventory-r1-2026-07-25/"
                "local-synthesis-inventory.v9.receipt.json",
                directory=False,
            )
        ),
        "frozenFourteenByTwoComparison": comparison,
        "primarySourceDocuments": documents,
        "modelMetadata": models,
        "licenceAndProvenance": licence,
        "synthesisMethod": method,
        "downloadPlan": plan,
        "candidateGate": {
            "candidateID": "openvoice-v2-melotts-english-en-br",
            "eligibility": eligibility,
            "passesPrimarySourceGate": True,
            "selectedForBoundDownload": True,
            "modelDownloadPermitted": True,
        },
        "executionState": {
            "sourceArchivesDownloaded": False,
            "modelFilesDownloaded": False,
            "runtimeInstalled": False,
            "runtimeDependencyLicenceLockPassed": False,
            "synthesisPermittedBeforeRuntimeDependencyLock": False,
            "synthesisExecuted": False,
            "audioFilesCreated": 0,
            "representativeGateRun": False,
            "fullGenerationPermitted": False,
            "completeMasterCount": 0,
            "candidatePromoted": False,
        },
        "cost": {
            "incrementalCostNOK": 0,
            "paidAPIUsed": False,
            "hostedSynthesisUsed": False,
        },
        "claimsExcluded": [
            "runtime compatibility",
            "Apple Silicon throughput",
            "representative audio quality",
            "identity-gate pass",
            "complete-master pass",
            "editor voice selection",
            "artistic approval",
            "shipping approval",
        ],
        "nextGate": (
            "Download only the exact whitelisted bytes, verify every hash, "
            "freeze an offline runtime and dependency-licence lock, then run "
            "the unchanged fourteen-utterance by two-reference comparison."
        ),
    }
    receipt_path = output / RECEIPT_NAME
    v8.write_json(receipt_path, receipt)
    audio_extensions = {".wav", ".aif", ".aiff", ".caf", ".m4a", ".mp3"}
    if any(path.suffix.lower() in audio_extensions for path in output.rglob("*")):
        raise v8.V8Error("primary-source preflight unexpectedly created audio")
    return {**receipt, "receipt": v8.file_binding(receipt_path)}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--primary-source-network", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = preflight(parse_args(sys.argv[1:] if argv is None else argv))
    except (OSError, v8.V8Error, json.JSONDecodeError) as error:
        print(f"v10 OpenVoice V2 preflight failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": receipt["status"], "receipt": receipt["receipt"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
