import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const authorities = [
  {
    path: "native/content/backstage/harvest/allocation-earth-donor-mask-v26.source-authority.json",
    sha256: "38620a09307373db3c4636377e38d795a9008160c7f115f8644084ee906f310f",
  },
  {
    path: "native/content/backstage/harvest/rear-ground-donor-mask-v26.source-authority.json",
    sha256: "8674909953d67c3dfff93eefa336d42e3bde7f14c74c7bc03e995accbf3928e5",
  },
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function readAuthority(entry) {
  return JSON.parse(await readFile(resolve(root, entry.path), "utf8"));
}

test("the Harvest donor authorities are byte-bound", async () => {
  for (const entry of authorities) {
    const authorityPath = resolve(root, entry.path);
    const authorityBytes = await readFile(authorityPath);
    const sidecar = (await readFile(`${authorityPath}.sha256`, "utf8")).trim();
    assert.equal(sha256(authorityBytes), entry.sha256, entry.path);
    assert.equal(sidecar, entry.sha256, entry.path);
  }
});

test("each authority binds its exact source, prompt and grayscale mask", async () => {
  for (const entry of authorities) {
    const authority = await readAuthority(entry);
    for (const input of [
      authority.sourceMaster,
      authority.promptSpecification,
      authority.selectedMask,
    ]) {
      const bytes = await readFile(resolve(root, input.path));
      assert.equal(sha256(bytes), input.sha256, input.path);
    }

    const maskBytes = await readFile(resolve(root, authority.selectedMask.path));
    assert.equal(maskBytes.length, authority.selectedMask.bytes);
    assert.deepEqual([...maskBytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
    assert.equal(maskBytes.readUInt32BE(16), 1290);
    assert.equal(maskBytes.readUInt32BE(20), 2796);
    assert.equal(maskBytes[24], 8, "mask must remain 8-bit");
    assert.equal(maskBytes[25], 0, "mask must remain grayscale");

    const prompt = JSON.parse(
      await readFile(resolve(root, authority.promptSpecification.path), "utf8"),
    );
    assert.equal(prompt.shippingState, "PROHIBITED");
    assert.equal(prompt.source.sha256, authority.sourceMaster.sha256);
    assert.equal(prompt.objects.length, 1);
    assert.equal(prompt.objects[0].id, authority.selectedMask.id);
    assert.equal(prompt.objects[0].selectedCandidate, authority.selectedMask.selectedCandidate);
  }
});

test("the donor mask cannot grant write, production or shipping authority", async () => {
  for (const entry of authorities) {
    const authority = await readAuthority(entry);
    assert.equal(authority.scope, "PATCHMATCH_DONOR_SELECTION_ONLY");
    assert.deepEqual(authority.authorityLimits, {
      editorApproval: false,
      productionAssetAuthority: false,
      productionMasterAuthority: false,
      packageAuthority: false,
      shippingAllowed: false,
      candidateMayEnterShippingCompiler: false,
      maskMayBeUsedAsLayerAlpha: false,
      maskMayAuthorizeWrittenPixels: false,
    });
    assert.equal(authority.deterministicReplay.allFilesByteIdentical, true);
    assert.equal(
      authority.deterministicReplay.firstReceiptSha256,
      authority.deterministicReplay.replayReceiptSha256,
    );
    assert.ok(authority.visualReview.prohibitedInterpretations.includes("SHIPPING_APPROVAL"));
  }
});
