import assert from 'node:assert/strict';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createConventionOperations } from '../src/conventions.mjs';
import { LIMITS } from '../src/limits.mjs';
import { PROFILE_TOOL_NAMES } from '../src/profiles.mjs';
import { createConventionsHandlers } from '../src/tools/conventions.mjs';

async function temporaryProject(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'blog-writer-conventions-'));
  await mkdir(path.join(root, 'inputs'));
  await writeFile(path.join(root, 'README.md'), 'read me\n');
  await writeFile(path.join(root, 'inputs', 'sentinel.md'), 'sentinel\n');
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

async function untouchedState(root) {
  return {
    rootNames: (await readdir(root)).sort(),
    readme: await readFile(path.join(root, 'README.md'), 'utf8'),
    sentinel: await readFile(path.join(root, 'inputs', 'sentinel.md'), 'utf8'),
  };
}

test('writeConventions_creates_only_the_root_CONVENTIONS_md', async (t) => {
  const root = await temporaryProject(t);
  const operations = createConventionOperations({ projectRoot: root });
  const before = await untouchedState(root);
  const content = '# Writing conventions\n\nUse clear prose.\n';

  const result = await operations.writeConventions({
    content,
    overwrite: false,
  });

  assert.equal(
    result.path,
    path.join(await realpath(root), 'CONVENTIONS.md'),
  );
  assert.equal(await readFile(path.join(root, 'CONVENTIONS.md'), 'utf8'), content);
  assert.equal(await readFile(path.join(root, 'README.md'), 'utf8'), before.readme);
  assert.equal(
    await readFile(path.join(root, 'inputs', 'sentinel.md'), 'utf8'),
    before.sentinel,
  );
  assert.deepEqual((await readdir(root)).sort(), [
    'CONVENTIONS.md',
    ...before.rootNames,
  ].sort());
});

test('writeConventions_rejects_empty_and_oversized_content_without_mutation', async (t) => {
  const root = await temporaryProject(t);
  const operations = createConventionOperations({ projectRoot: root });
  const before = await untouchedState(root);

  for (const content of ['', ' \n\t', 'a'.repeat(LIMITS.generatedFileBytes + 1)]) {
    await assert.rejects(
      operations.writeConventions({ content, overwrite: false }),
      /empty|content|size|large|byte/i,
    );
    assert.deepEqual(await untouchedState(root), before);
  }
  await assert.rejects(readFile(path.join(root, 'CONVENTIONS.md')), {
    code: 'ENOENT',
  });
});

test('writeConventions_requires_explicit_overwrite_and_preserves_collisions', async (t) => {
  const root = await temporaryProject(t);
  const target = path.join(root, 'CONVENTIONS.md');
  const original = '# Original\n';
  const replacement = '# Replacement\n';
  await writeFile(target, original);
  const operations = createConventionOperations({ projectRoot: root });

  await assert.rejects(
    operations.writeConventions({ content: replacement, overwrite: false }),
    /overwrite|exists|collision/i,
  );
  assert.equal(await readFile(target, 'utf8'), original);

  await operations.writeConventions({ content: replacement, overwrite: true });
  assert.equal(await readFile(target, 'utf8'), replacement);
});

test('writeConventions_rejects_a_root_target_symlink', async (t) => {
  const root = await temporaryProject(t);
  const outside = await mkdtemp(path.join(tmpdir(), 'blog-writer-conventions-outside-'));
  t.after(() => rm(outside, { recursive: true, force: true }));
  const outsideTarget = path.join(outside, 'outside.md');
  await writeFile(outsideTarget, 'outside\n');
  await symlink(outsideTarget, path.join(root, 'CONVENTIONS.md'));
  const operations = createConventionOperations({ projectRoot: root });

  await assert.rejects(
    operations.writeConventions({ content: '# Replacement\n', overwrite: true }),
    /symlink/i,
  );
  assert.equal(await readFile(outsideTarget, 'utf8'), 'outside\n');
});

test('createConventionsHandlers_has_only_the_scoped_convention_tool_and_arguments', async (t) => {
  const root = await temporaryProject(t);
  const handlers = createConventionsHandlers({ projectRoot: root });

  assert.deepEqual(Object.keys(handlers), ['write_conventions']);
  assert.deepEqual(PROFILE_TOOL_NAMES.conventions, ['write_conventions']);
  assert.deepEqual(
    Object.keys(handlers.write_conventions.config.inputSchema.shape).sort(),
    ['content', 'overwrite'],
  );
  assert.equal(
    handlers.write_conventions.config.inputSchema.safeParse({
      content: '# Conventions\n',
    }).success,
    false,
  );

  const response = await handlers.write_conventions.handler({
    content: '# Conventions\n',
    overwrite: false,
  });
  assert.equal(response.isError, undefined);
  assert.equal(
    await readFile(path.join(root, 'CONVENTIONS.md'), 'utf8'),
    '# Conventions\n',
  );
});

test('createConventionsHandlers_returns_a_sanitized_structured_failure', async () => {
  const handlers = createConventionsHandlers({
    conventionOperations: {
      writeConventions: async () => {
        throw new Error('token=must-not-leak /private/conventions');
      },
    },
  });

  const response = await handlers.write_conventions.handler({
    content: '# Conventions\n',
    overwrite: true,
  });

  assert.deepEqual(response.structuredContent, {
    code: 'conventions_write_failed',
    operation: 'write_conventions',
  });
  assert.equal(response.isError, true);
  assert.doesNotMatch(JSON.stringify(response), /must-not-leak|private/i);
});
