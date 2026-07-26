import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import {
  mkdtemp,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const scriptPath = path.join(repositoryRoot, "native/scripts/visual-asset-production.mjs");

async function rejectsCLI(arguments_, pattern) {
  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, ...arguments_], { cwd: repositoryRoot }),
    (error) => pattern.test(`${error.stderr ?? ""}${error.stdout ?? ""}`),
  );
}

test("provisional freeze authority cannot be written outside the backstage tree", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-cli-"));
  try {
    await rejectsCLI([
      "freeze-provisional-master",
      "--candidate", path.join(root, "candidate.png"),
      "--metadata", path.join(root, "candidate.metadata.json"),
      "--authority", path.join(root, "authority.json"),
    ], /provisional authority must remain under native\/content\/backstage/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("provisional build cannot target a public or arbitrary output tree", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-cli-"));
  try {
    const dagPath = path.join(root, "dag.json");
    await writeFile(dagPath, `${JSON.stringify({
      buildMode: "CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT",
    })}\n`);
    await rejectsCLI([
      "build",
      "--dag", dagPath,
      "--output", path.join(root, "public-output"),
      "--receipt", path.join(root, "receipt.json"),
    ], /provisional visual output must remain under native\/.build/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("provisional DAG and receipt cannot leave backstage even when output is a development path", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "long-west-visual-cli-"));
  try {
    const dagPath = path.join(root, "dag.json");
    await writeFile(dagPath, `${JSON.stringify({
      buildMode: "CODEX_PROVISIONAL_NON_SHIPPING_DEVELOPMENT",
    })}\n`);
    await rejectsCLI([
      "build",
      "--dag", dagPath,
      "--output", path.join(repositoryRoot, "native/.build/visual-cli-boundary-test"),
      "--receipt", path.join(root, "receipt.json"),
    ], /provisional visual DAG and receipt must remain under native\/content\/backstage/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
