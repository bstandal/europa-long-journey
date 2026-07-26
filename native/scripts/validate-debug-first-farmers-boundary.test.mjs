import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const nativeRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const iosRoot = join(nativeRoot, 'ios');

async function source(path) {
  return readFile(join(iosRoot, path), 'utf8');
}

test('development repository and app loader do not exist outside DEBUG compilation', async () => {
  for (const path of [
    'Sources/JourneyContent/DevelopmentFirstFarmersRepository.swift',
    'Sources/JourneyApp/DevelopmentFirstFarmersAppContent.swift',
  ]) {
    const text = (await source(path)).trim();
    assert.ok(text.startsWith('#if DEBUG'), `${path} must begin at the DEBUG boundary`);
    assert.ok(text.endsWith('#endif'), `${path} must end at the DEBUG boundary`);
  }
});

test('generated development payload resources are copied only into Debug builds', async () => {
  const project = await source('project.yml');
  for (const resource of [
    'first-farmers.content-package.json',
    'first-farmers.payload-receipt.json',
  ]) {
    assert.ok(project.includes(`path: ../phase2/generated/${resource}`));
    const releaseSettings = project.slice(project.indexOf('      configs:'));
    assert.ok(releaseSettings.includes(`            - ${resource}`));
  }
  assert.match(project, /configs:\s*\n\s*Release:/);
});

test('app chapter route is coordinator-driven and the public content tree remains empty', async () => {
  const model = await source('Sources/JourneyApp/JourneyModel.swift');
  const rootView = await source('Sources/JourneyApp/RootView.swift');
  assert.match(model, /ChapterCoordinator/);
  assert.match(model, /advanceActions\(state: committedState\)/);
  assert.doesNotMatch(rootView, /ChapterFoundationView/);

  const publicRoot = join(nativeRoot, 'content/public');
  if (existsSync(publicRoot)) {
    const entries = await readdir(publicRoot, { recursive: true });
    assert.deepEqual(entries, []);
  }
});
