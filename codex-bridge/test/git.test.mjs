import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import test from 'node:test';

import { collectGitCommits } from '../src/git.mjs';

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

async function createRepository(t) {
  const directory = await temporaryDirectory(t, 'blog-writer-git-');
  await git(directory, ['init', '--quiet']);
  await git(directory, ['config', 'user.name', 'Synthetic Tester']);
  await git(directory, ['config', 'user.email', 'synthetic@example.invalid']);

  const commits = [
    ['2026-09-19T23:59:59.000Z', 'before window'],
    ['2026-09-20T00:00:00.000Z', 'at open lower bound'],
    ['2026-09-20T12:00:00.000Z', 'inside window'],
    ['2026-09-21T00:00:00.000Z', 'at closed upper bound'],
    ['2026-09-21T00:00:01.000Z', 'after window'],
  ];
  for (const [date, subject] of commits) {
    await writeFile(path.join(directory, 'activity.txt'), `${subject}\n`);
    await git(directory, ['add', 'activity.txt']);
    await git(directory, ['commit', '--quiet', '-m', subject], {
      env: {
        ...process.env,
        GIT_AUTHOR_DATE: date,
        GIT_COMMITTER_DATE: date,
      },
    });
  }
  await writeFile(path.join(directory, 'untracked.txt'), 'preserve me\n');
  return directory;
}

test('collectGitCommits_returns_only_open_closed_window_records_without_mutation', async (t) => {
  const repository = await createRepository(t);
  const before = await git(repository, ['status', '--porcelain=v1']);

  const result = await collectGitCommits({
    projects: [repository],
    lo: LO,
    hi: HI,
  });

  const after = await git(repository, ['status', '--porcelain=v1']);
  assert.equal(after.stdout, before.stdout);
  assert.deepEqual(
    result.records.map(({ title, timestamp }) => ({ title, timestamp })),
    [
      {
        title: 'inside window',
        timestamp: '2026-09-20T12:00:00.000Z',
      },
      {
        title: 'at closed upper bound',
        timestamp: '2026-09-21T00:00:00.000Z',
      },
    ]
  );
  for (const record of result.records) {
    assert.equal(record.source, 'git');
    assert.equal(record.project_dir, repository);
    assert.equal(record.kind, 'commit');
    assert.match(record.id, /^[a-f0-9]{40}$/);
    assert.equal(record.text, record.title);
    assert.deepEqual(record.metadata, {
      sha: record.id,
      short_sha: record.id.slice(0, 7),
      subject: record.title,
    });
  }
  assert.deepEqual(result.warnings, []);
});

test('collectGitCommits_warns_and_skips_missing_and_non_git_projects', async (t) => {
  const root = await temporaryDirectory(t, 'blog-writer-not-git-');
  const nonGit = path.join(root, 'plain');
  const missing = path.join(root, 'missing');
  await mkdir(nonGit);

  const result = await collectGitCommits({
    projects: [missing, nonGit],
    lo: LO,
    hi: HI,
  });
  const serialized = JSON.stringify(result.warnings);

  assert.deepEqual(result.records, []);
  assert.equal(result.warnings.length, 2);
  assert.match(serialized, /git collection failed/i);
  assert.doesNotMatch(serialized, /fatal:|ENOENT|stack/i);
});
