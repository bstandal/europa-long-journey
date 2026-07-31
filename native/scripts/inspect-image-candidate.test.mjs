#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";
import { analyseLuma, evaluateCandidate } from "./inspect-image-candidate.mjs";

const limits = {
  minWidth: 1290,
  minHeight: 2796,
  minimumLumaRange: 24,
  minimumLumaStandardDeviation: 10,
  minimumMeanLuma: 3,
  maximumMeanLuma: 252,
  maximumNearBlackFraction: 0.97,
  maximumNearWhiteFraction: 0.97,
};

test("uniform black output fails before visual review", () => {
  const luma = analyseLuma(new Uint8Array(96 * 96));
  const failures = evaluateCandidate({
    width: 1296,
    height: 2800,
    formatName: "png_pipe",
    luma,
  }, limits);

  assert.ok(failures.some((failure) => failure.includes("luma range")));
  assert.ok(failures.some((failure) => failure.includes("effectively black")));
  assert.ok(failures.some((failure) => failure.includes("near-black fraction")));
});

test("varied full-resolution PNG reaches manual-review boundary", () => {
  const sample = Uint8Array.from({ length: 96 * 96 }, (_, index) => index % 224 + 16);
  const luma = analyseLuma(sample);
  const failures = evaluateCandidate({
    width: 1296,
    height: 2800,
    formatName: "png_pipe",
    luma,
  }, limits);

  assert.deepEqual(failures, []);
});

test("valid pixels cannot conceal an undersized master", () => {
  const sample = Uint8Array.from({ length: 96 * 96 }, (_, index) => index % 224 + 16);
  const luma = analyseLuma(sample);
  const failures = evaluateCandidate({
    width: 941,
    height: 1672,
    formatName: "png_pipe",
    luma,
  }, limits);

  assert.ok(failures.some((failure) => failure.includes("width")));
  assert.ok(failures.some((failure) => failure.includes("height")));
});

