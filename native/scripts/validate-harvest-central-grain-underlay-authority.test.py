#!/usr/bin/env python3
"""Regression tests for Harvest central-grain source authority."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "native/scripts/validate-harvest-central-grain-underlay-authority.py"


def load_validator():
    specification = importlib.util.spec_from_file_location("harvest_underlay_authority", VALIDATOR_PATH)
    if specification is None or specification.loader is None:
        raise RuntimeError("Cannot import Harvest underlay authority validator")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


validator = load_validator()


class HarvestUnderlayAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.authority = json.loads(validator.AUTHORITY_PATH.read_text(encoding="utf-8"))
        cls.contract = json.loads(validator.CONTRACT_PATH.read_text(encoding="utf-8"))

    def test_exact_integrated_authority_passes(self) -> None:
        validator.validate_authority()

    def test_shipping_claim_fails_closed(self) -> None:
        authority = copy.deepcopy(self.authority)
        authority["authorityLimits"]["shippingAllowed"] = True
        with self.assertRaisesRegex(validator.AuthorityValidationError, "forbidden authority"):
            validator.validate_authority_document(authority, self.contract)

    def test_semantic_grain_mask_cannot_replace_authorization_t(self) -> None:
        authority = copy.deepcopy(self.authority)
        authority["initialStateRecomposition"]["restoreMask"] = "SEMANTIC_G"
        with self.assertRaisesRegex(validator.AuthorityValidationError, "restore all of T"):
            validator.validate_authority_document(authority, self.contract)

    def test_contract_cannot_drift_from_authority_hash(self) -> None:
        contract = copy.deepcopy(self.contract)
        underlay = validator.central_underlay(contract)
        underlay["recipe"]["sourceAuthority"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(validator.AuthorityValidationError, "source-authority hash drifted"):
            validator.validate_authority_document(self.authority, contract)

    def test_receipt_binding_cannot_be_substituted(self) -> None:
        authority = copy.deepcopy(self.authority)
        authority["technicalReceipt"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(validator.AuthorityValidationError, "receipt binding drifted"):
            validator.validate_authority_document(authority, self.contract)


if __name__ == "__main__":
    unittest.main()
