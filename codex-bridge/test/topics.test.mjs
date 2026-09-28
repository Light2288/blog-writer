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

import { createTopicOperations } from '../src/topics.mjs';
import { createTopicHandlers } from '../src/tools/topic.mjs';

const DATE = '2026-09-28';
const DRAFT = '# Candidate topics\n\nStatus: DRAFT\n\nOne topic.\n';

async function temporaryProject(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'blog-writer-topics-'));
  await mkdir(path.join(root, 'inputs'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

function target(root, date = DATE) {
  return path.join(root, 'inputs', `topics-${date}.md`);
}

async function canonicalTarget(root, date = DATE) {
  return path.join(await realpath(root), 'inputs', `topics-${date}.md`);
}

async function inputState(root) {
  const names = (await readdir(path.join(root, 'inputs'))).sort();
  const files = await Promise.all(
    names.map(async (name) => [
      name,
      await readFile(path.join(root, 'inputs', name)),
    ]),
  );
  return files;
}

test('writeTopicDraft_writes_only_the_canonical_dated_topic_target', async (t) => {
  const root = await temporaryProject(t);
  const operations = createTopicOperations({ projectRoot: root });

  const result = await operations.writeTopicDraft({
    date: DATE,
    content: DRAFT,
    overwrite: false,
  });

  assert.equal(result.path, await canonicalTarget(root));
  assert.equal(await readFile(target(root), 'utf8'), DRAFT);
  assert.deepEqual(await readdir(root), ['inputs']);

  const before = await inputState(root);
  for (const invalidDate of ['../escape', '2026-02-29', '2026-9-28']) {
    await assert.rejects(
      operations.writeTopicDraft({
        date: invalidDate,
        content: DRAFT,
        overwrite: true,
      }),
      /date/i,
    );
    assert.deepEqual(await inputState(root), before);
  }
});

test('writeTopicDraft_requires_exactly_one_Status_DRAFT_marker', async (t) => {
  const root = await temporaryProject(t);
  const operations = createTopicOperations({ projectRoot: root });
  const invalidContents = [
    '# Missing marker\n',
    'Status: FINAL\n',
    'Status: DRAFT\nbody\nStatus: DRAFT\n',
    ' Status: DRAFT\n',
  ];

  for (const content of invalidContents) {
    await assert.rejects(
      operations.writeTopicDraft({ date: DATE, content, overwrite: false }),
      /exactly one.*Status: DRAFT/i,
    );
    assert.deepEqual(await inputState(root), []);
  }
});

test('writeTopicDraft_requires_explicit_overwrite_and_preserves_collisions', async (t) => {
  const root = await temporaryProject(t);
  const operations = createTopicOperations({ projectRoot: root });
  await writeFile(target(root), DRAFT);
  const replacement = '# Revised\n\nStatus: DRAFT\n\nRevised topic.\n';

  await assert.rejects(
    operations.writeTopicDraft({
      date: DATE,
      content: replacement,
      overwrite: false,
    }),
    /overwrite|exists|collision/i,
  );
  assert.equal(await readFile(target(root), 'utf8'), DRAFT);

  await operations.writeTopicDraft({
    date: DATE,
    content: replacement,
    overwrite: true,
  });
  assert.equal(await readFile(target(root), 'utf8'), replacement);
});

test('writeTopicDraft_rejects_a_symlink_target_without_touching_its_destination', async (t) => {
  const root = await temporaryProject(t);
  const outside = await mkdtemp(path.join(tmpdir(), 'blog-writer-topic-outside-'));
  t.after(() => rm(outside, { recursive: true, force: true }));
  const outsideTarget = path.join(outside, 'outside.md');
  await writeFile(outsideTarget, 'outside\n');
  await symlink(outsideTarget, target(root));
  const operations = createTopicOperations({ projectRoot: root });

  await assert.rejects(
    operations.writeTopicDraft({
      date: DATE,
      content: DRAFT,
      overwrite: true,
    }),
    /symlink/i,
  );
  assert.equal(await readFile(outsideTarget, 'utf8'), 'outside\n');
});

test('finalizeTopics_changes_only_the_single_Status_marker', async (t) => {
  const root = await temporaryProject(t);
  const operations = createTopicOperations({ projectRoot: root });
  const draft = '\uFEFF# Tópics\r\nStatus: DRAFT\r\n\r\nBytes stay: DRAFT\r\n';
  await operations.writeTopicDraft({
    date: DATE,
    content: draft,
    overwrite: false,
  });

  const result = await operations.finalizeTopics({ date: DATE });
  const finalized = await readFile(target(root), 'utf8');

  assert.equal(result.path, await canonicalTarget(root));
  assert.equal(finalized, draft.replace('Status: DRAFT', 'Status: FINAL'));
  assert.equal(
    finalized.replace('Status: FINAL', 'Status: DRAFT'),
    draft,
  );
});

test('finalizeTopics_rejects_missing_duplicate_and_already_final_markers_without_changes', async (t) => {
  const cases = [
    '# Missing marker\n',
    'Status: DRAFT\nbody\nStatus: DRAFT\n',
    'Status: FINAL\n',
  ];

  for (const content of cases) {
    await t.test(content.split('\n')[0], async (subtest) => {
      const root = await temporaryProject(subtest);
      await writeFile(target(root), content);
      const operations = createTopicOperations({ projectRoot: root });
      const before = await inputState(root);

      await assert.rejects(
        operations.finalizeTopics({ date: DATE }),
        /exactly one.*Status: DRAFT/i,
      );
      assert.deepEqual(await inputState(root), before);
    });
  }
});

test('createTopicHandlers_exposes_only_the_topic_mutation_arguments', async (t) => {
  const root = await temporaryProject(t);
  const handlers = createTopicHandlers({ projectRoot: root });
  assert.deepEqual(
    Object.keys(handlers.write_topic_draft.config.inputSchema.shape).sort(),
    ['content', 'date', 'overwrite'],
  );
  assert.deepEqual(
    Object.keys(handlers.finalize_topics.config.inputSchema.shape),
    ['date'],
  );
  assert.equal(
    handlers.write_topic_draft.config.inputSchema.safeParse({
      date: DATE,
      content: DRAFT,
    }).success,
    false,
  );

  const written = await handlers.write_topic_draft.handler({
    date: DATE,
    content: DRAFT,
    overwrite: false,
  });
  const finalized = await handlers.finalize_topics.handler({ date: DATE });

  assert.equal(written.isError, undefined);
  assert.equal(finalized.isError, undefined);
  assert.equal(await readFile(target(root), 'utf8'), DRAFT.replace('DRAFT', 'FINAL'));
});
