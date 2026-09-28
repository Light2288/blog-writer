import assert from 'node:assert/strict';
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  assertContainedTarget,
  assertValidDate,
} from '../src/paths.mjs';
import { atomicWrite } from '../src/atomic.mjs';
import { LIMITS } from '../src/limits.mjs';

async function temporaryProject(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'blog-writer-paths-'));
  const outside = await mkdtemp(path.join(tmpdir(), 'blog-writer-outside-'));
  await mkdir(path.join(root, 'inputs'));
  t.after(() => rm(root, { recursive: true, force: true }));
  t.after(() => rm(outside, { recursive: true, force: true }));
  return { root, outside };
}

function topicPolicy(date = '2026-09-28') {
  return {
    exactRelativePath: `inputs/topics-${date}.md`,
    extension: '.md',
  };
}

test('assertContainedTarget_accepts_only_the_exact_relative_target', async (t) => {
  const { root } = await temporaryProject(t);
  const target = path.join(root, 'inputs', 'topics-2026-09-28.md');

  assert.equal(
    await assertContainedTarget(root, target, topicPolicy()),
    path.join(await realpath(root), 'inputs', 'topics-2026-09-28.md'),
  );
  await assert.rejects(
    assertContainedTarget(root, path.join(root, '..', 'escape.md'), topicPolicy()),
    /outside|target/i,
  );
  await assert.rejects(
    assertContainedTarget(root, path.join(tmpdir(), 'absolute-escape.md'), topicPolicy()),
    /outside|target/i,
  );
  await assert.rejects(
    assertContainedTarget(
      root,
      path.join(root, 'inputs', 'topics-2026-09-28.mdx'),
      { relativeDirectory: 'inputs', extension: '.md' },
    ),
    /extension/i,
  );
});

test('assertContainedTarget_rejects_existing_target_and_parent_symlinks', async (t) => {
  const targetCase = await temporaryProject(t);
  const outsideTarget = path.join(targetCase.outside, 'outside.md');
  await writeFile(outsideTarget, 'outside\n');
  const target = path.join(
    targetCase.root,
    'inputs',
    'topics-2026-09-28.md',
  );
  await symlink(outsideTarget, target);

  await assert.rejects(
    assertContainedTarget(targetCase.root, target, topicPolicy()),
    /symlink/i,
  );

  const parentCase = await temporaryProject(t);
  await rm(path.join(parentCase.root, 'inputs'), { recursive: true });
  await symlink(parentCase.outside, path.join(parentCase.root, 'inputs'));

  await assert.rejects(
    assertContainedTarget(
      parentCase.root,
      path.join(parentCase.root, 'inputs', 'topics-2026-09-28.md'),
      topicPolicy(),
    ),
    /symlink/i,
  );
});

test('assertValidDate_rejects_non_calendar_and_non_canonical_dates', () => {
  assert.equal(assertValidDate('2026-09-28'), '2026-09-28');
  for (const invalid of ['2026-02-29', '2026-9-28', '../2026-09-28', 'nope']) {
    assert.throws(() => assertValidDate(invalid), /date/i);
  }
});

test('atomicWrite_enforces_the_1_MiB_boundary_and_collision_approval', async (t) => {
  const { root } = await temporaryProject(t);
  const exactBoundary = path.join(root, 'inputs', 'boundary.md');
  await atomicWrite(exactBoundary, 'a'.repeat(LIMITS.generatedFileBytes), {
    maxBytes: LIMITS.generatedFileBytes,
  });
  assert.equal((await lstat(exactBoundary)).size, LIMITS.generatedFileBytes);

  const oversized = path.join(root, 'inputs', 'oversized.md');
  await assert.rejects(
    atomicWrite(oversized, 'a'.repeat(LIMITS.generatedFileBytes + 1), {
      maxBytes: LIMITS.generatedFileBytes,
    }),
    /size|large|byte/i,
  );
  await assert.rejects(lstat(oversized), { code: 'ENOENT' });

  await assert.rejects(
    atomicWrite(exactBoundary, 'replacement', {
      maxBytes: LIMITS.generatedFileBytes,
    }),
    /exists|overwrite|collision/i,
  );
  assert.equal((await readFile(exactBoundary, 'utf8')).length, LIMITS.generatedFileBytes);

  await atomicWrite(exactBoundary, 'replacement', {
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: true,
  });
  assert.equal(await readFile(exactBoundary, 'utf8'), 'replacement');
  assert.equal((await lstat(exactBoundary)).mode & 0o777, 0o600);
});

test('atomicWrite_rejects_a_target_swapped_to_a_symlink_before_rename', async (t) => {
  const { root, outside } = await temporaryProject(t);
  const target = path.join(root, 'inputs', 'topics-2026-09-28.md');
  const outsideTarget = path.join(outside, 'outside.md');
  await writeFile(target, 'original\n');
  await writeFile(outsideTarget, 'outside\n');

  await assert.rejects(
    atomicWrite(target, 'replacement\n', {
      overwrite: true,
      beforeRename: async () => {
        await rm(target);
        await symlink(outsideTarget, target);
      },
    }),
    /changed|symlink|replace/i,
  );

  assert.equal(await readFile(outsideTarget, 'utf8'), 'outside\n');
  assert.equal((await lstat(target)).isSymbolicLink(), true);
  assert.deepEqual((await readdir(path.dirname(target))).sort(), [
    path.basename(target),
  ]);
});

test('atomicWrite_removes_its_temporary_file_when_rename_fails', async (t) => {
  const { root } = await temporaryProject(t);
  const target = path.join(root, 'inputs', 'topics-2026-09-28.md');
  await writeFile(target, 'original\n');

  const fsOps = {
    chmod,
    lstat,
    rename: async () => {
      throw new Error('synthetic rename failure');
    },
    rm,
  };

  await assert.rejects(
    atomicWrite(target, 'replacement\n', { fsOps, overwrite: true }),
    /synthetic rename failure/,
  );
  assert.equal(await readFile(target, 'utf8'), 'original\n');
  assert.deepEqual(await readdir(path.dirname(target)), [path.basename(target)]);
});
