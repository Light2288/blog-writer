import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, rm, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { promisify } from 'node:util';

import { collectActivity } from '../src/activity.mjs';
import { LIMITS } from '../src/limits.mjs';
import { createTopicHandlers } from '../src/tools/topic.mjs';

const run = promisify(execFile);
const LO = Date.parse('2026-09-20T00:00:00.000Z');
const HI = Date.parse('2026-09-21T00:00:00.000Z');

async function temporaryDirectory(t, prefix) {
  const directory = await mkdtemp(path.join(tmpdir(), prefix));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

async function git(directory, args, options = {}) {
  return run('git', ['-C', directory, ...args], options);
}

async function repository(t, commit = true) {
  const directory = await temporaryDirectory(t, 'blog-writer-activity-git-');
  await git(directory, ['init', '--quiet']);
  await git(directory, ['config', 'user.name', 'Synthetic Tester']);
  await git(directory, ['config', 'user.email', 'synthetic@example.invalid']);
  if (commit) {
    await writeFile(path.join(directory, 'activity.txt'), 'activity\n');
    await git(directory, ['add', 'activity.txt']);
    await git(directory, ['commit', '--quiet', '-m', 'activity commit'], {
      env: {
        ...process.env,
        GIT_AUTHOR_DATE: '2026-09-20T12:00:00.000Z',
        GIT_COMMITTER_DATE: '2026-09-20T12:00:00.000Z',
      },
    });
  }
  return directory;
}

async function codexHome(t) {
  const root = await temporaryDirectory(t, 'blog-writer-activity-home-');
  const sessions = path.join(root, 'sessions');
  await mkdir(sessions);
  return { root, sessions };
}

function rollout({ id, cwd, timestamp, text = 'session text' }) {
  return [
    JSON.stringify({
      timestamp,
      type: 'session_meta',
      payload: { id, cwd, title: `Title ${id}` },
    }),
    JSON.stringify({
      timestamp,
      type: 'response_item',
      payload: {
        id: `${id}-message`,
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text }],
      },
    }),
  ].join('\n');
}

async function writeRollout(target, content) {
  await writeFile(target, `${content}\n`);
  await utimes(target, new Date(HI + 1_000), new Date(HI + 1_000));
}

test('collectActivity_filters_confirmed_projects_sorts_records_and_combines_stats_and_warnings', async (t) => {
  const confirmed = await repository(t);
  const expectedSha = (await git(confirmed, ['rev-parse', 'HEAD'])).stdout.trim();
  const unconfirmed = await repository(t, false);
  const missing = path.join(await temporaryDirectory(t, 'missing-parent-'), 'missing');
  const home = await codexHome(t);
  await writeRollout(
    path.join(home.sessions, 'confirmed.jsonl'),
    `${rollout({
      id: 'session-confirmed',
      cwd: confirmed,
      timestamp: '2026-09-20T12:00:00.000Z',
    })}\nmalformed raw secret token=never-return`
  );
  await writeRollout(
    path.join(home.sessions, 'unconfirmed.jsonl'),
    rollout({
      id: 'session-unconfirmed',
      cwd: unconfirmed,
      timestamp: '2026-09-20T11:00:00.000Z',
    })
  );

  const result = await collectActivity({
    codexHome: home.root,
    confirmedProjects: [confirmed, missing],
    lo: LO,
    hi: HI,
  });

  assert.deepEqual(
    result.records.map(({ source, id }) => ({ source, id })),
    [
      { source: 'codex', id: 'session-confirmed' },
      { source: 'git', id: expectedSha },
    ]
  );
  assert.equal(result.records.some(({ project_dir }) => project_dir === unconfirmed), false);
  assert.equal(result.stats.codexRecords, 1);
  assert.equal(result.stats.gitRecords, 1);
  assert.equal(result.stats.totalRecords, 2);
  assert.equal(result.stats.malformedLines, 1);
  assert.equal(result.warnings.length, 2);
  assert.doesNotMatch(JSON.stringify(result.warnings), /never-return|fatal:|ENOENT/);
});

test('collectActivity_fails_on_missing_history_but_accepts_a_valid_empty_window', async (t) => {
  const project = await repository(t, false);
  const missingHome = await temporaryDirectory(t, 'missing-codex-home-');

  await assert.rejects(
    collectActivity({
      codexHome: missingHome,
      confirmedProjects: [project],
      lo: LO,
      hi: HI,
    }),
    /Codex history directory is unavailable/i
  );

  const home = await codexHome(t);
  const outsideWindow = path.join(home.sessions, 'outside-window.jsonl');
  await writeRollout(
    outsideWindow,
    rollout({
      id: 'outside-window',
      cwd: project,
      timestamp: '2026-09-19T12:00:00.000Z',
    })
  );
  await utimes(
    outsideWindow,
    new Date(LO - 1_000),
    new Date(LO - 1_000)
  );
  const empty = await collectActivity({
    codexHome: home.root,
    confirmedProjects: [project],
    lo: LO,
    hi: HI,
  });

  assert.deepEqual(empty.records, []);
  assert.equal(empty.stats.totalRecords, 0);
});

test('collectActivity_applies_transcript_limit_before_appending_git_records', async (t) => {
  const project = await repository(t);
  const home = await codexHome(t);
  const writes = [];
  for (let index = 0; index < 21; index += 1) {
    writes.push(
      writeRollout(
        path.join(home.sessions, `${index}.jsonl`),
        rollout({
          id: `session-${index}`,
          cwd: project,
          timestamp: new Date(LO + index + 1).toISOString(),
          text: 'word '.repeat(LIMITS.charactersPerSession / 5),
        })
      )
    );
  }
  await Promise.all(writes);

  const result = await collectActivity({
    codexHome: home.root,
    confirmedProjects: [project],
    lo: LO,
    hi: HI,
  });
  const codexRecords = result.records.filter(({ source }) => source === 'codex');
  const gitRecords = result.records.filter(({ source }) => source === 'git');

  assert.equal(
    codexRecords.reduce((total, record) => total + record.text.length, 0),
    LIMITS.transcriptCharacters
  );
  assert.equal(gitRecords.length, 1);
  assert.equal(result.stats.transcriptTruncated, true);
  assert.equal(result.stats.totalRecords, 21);
});

test('createTopicHandlers_validates_bounds_and_paths_without_leaking_exceptions', async () => {
  const handlers = createTopicHandlers({
    collectActivityImpl: async () => {
      throw new Error('raw secret token=must-not-leak');
    },
    scanRolloutsImpl: async () => {
      throw new Error('raw discovery secret');
    },
  });

  const invalidBounds = await handlers.discover_projects.handler({
    lo: HI,
    hi: LO,
  });
  const relativePath = await handlers.collect_activity.handler({
    lo: LO,
    hi: HI,
    confirmed_projects: ['relative/project'],
  });
  const operationFailure = await handlers.collect_activity.handler({
    lo: LO,
    hi: HI,
    confirmed_projects: ['/absolute/project'],
  });

  assert.equal(invalidBounds.isError, true);
  assert.equal(relativePath.isError, true);
  assert.equal(operationFailure.isError, true);
  assert.deepEqual(invalidBounds.structuredContent, {
    code: 'invalid_arguments',
    operation: 'discover_projects',
  });
  assert.deepEqual(relativePath.structuredContent, {
    code: 'invalid_arguments',
    operation: 'collect_activity',
  });
  assert.deepEqual(operationFailure.structuredContent, {
    code: 'collect_activity_failed',
    operation: 'collect_activity',
  });
  assert.doesNotMatch(
    JSON.stringify([invalidBounds, relativePath, operationFailure]),
    /raw secret|must-not-leak|raw discovery/i
  );
});
