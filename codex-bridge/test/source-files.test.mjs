import assert from 'node:assert/strict';
import {
  mkdir,
  mkdtemp,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { readSourceFile } from '../src/source-files.mjs';

async function temporaryDirectory(t, prefix) {
  const directory = await mkdtemp(path.join(tmpdir(), prefix));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test('readSourceFile_requires_an_absolute_requested_path', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  await writeFile(path.join(project, 'article.txt'), 'bounded evidence\n');

  await assert.rejects(
    readSourceFile({
      path: 'article.txt',
      confirmedProjects: [project],
    }),
    /absolute/i,
  );
});

test('readSourceFile_requires_a_nonempty_confirmed_project_list', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const source = path.join(project, 'article.txt');
  await writeFile(source, 'bounded evidence\n');

  await assert.rejects(
    readSourceFile({ path: source, confirmedProjects: [] }),
    /confirmed project/i,
  );
});

test('readSourceFile_reads_UTF_8_only_within_a_confirmed_project', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const outside = await temporaryDirectory(t, 'blog-writer-source-outside-');
  const source = path.join(project, 'notes', 'evidence.txt');
  const outsideSource = path.join(outside, 'secret.txt');
  await mkdir(path.dirname(source));
  await writeFile(source, 'caffè and facts\n');
  await writeFile(outsideSource, 'outside\n');

  assert.deepEqual(
    await readSourceFile({ path: source, confirmedProjects: [project] }),
    {
      path: await realpath(source),
      text: 'caffè and facts\n',
      truncated: false,
    },
  );
  await assert.rejects(
    readSourceFile({ path: outsideSource, confirmedProjects: [project] }),
    /confirmed project|outside/i,
  );
});

test('readSourceFile_rejects_symlink_escapes', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const outside = await temporaryDirectory(t, 'blog-writer-source-outside-');
  const outsideSource = path.join(outside, 'secret.txt');
  const link = path.join(project, 'linked-secret.txt');
  await writeFile(outsideSource, 'outside\n');
  await symlink(outsideSource, link);

  await assert.rejects(
    readSourceFile({ path: link, confirmedProjects: [project] }),
    /symlink|confirmed project|outside/i,
  );
});

test('readSourceFile_rejects_directories_and_binary_content', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const binary = path.join(project, 'binary.dat');
  await writeFile(binary, Buffer.from([0x74, 0x65, 0x78, 0x74, 0x00, 0xff]));

  await assert.rejects(
    readSourceFile({ path: project, confirmedProjects: [project] }),
    /regular file|directory/i,
  );
  await assert.rejects(
    readSourceFile({ path: binary, confirmedProjects: [project] }),
    /UTF-?8|binary|text/i,
  );
});

test('readSourceFile_rejects_invalid_UTF_8_beyond_the_returned_prefix', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const source = path.join(project, 'long-invalid.txt');
  await writeFile(
    source,
    Buffer.concat([Buffer.from('a'.repeat(90_000)), Buffer.from([0xff])]),
  );

  await assert.rejects(
    readSourceFile({ path: source, confirmedProjects: [project] }),
    /UTF-?8|binary|text/i,
  );
});

test('readSourceFile_truncates_at_exactly_20000_characters', async (t) => {
  const project = await temporaryDirectory(t, 'blog-writer-source-');
  const exact = path.join(project, 'exact.txt');
  const long = path.join(project, 'long.txt');
  await writeFile(exact, 'a'.repeat(20_000));
  await writeFile(long, `${'b'.repeat(20_000)}tail`);

  const exactResult = await readSourceFile({
    path: exact,
    confirmedProjects: [project],
  });
  const longResult = await readSourceFile({
    path: long,
    confirmedProjects: [project],
  });

  assert.equal(exactResult.text.length, 20_000);
  assert.equal(exactResult.truncated, false);
  assert.equal(longResult.text, 'b'.repeat(20_000));
  assert.equal(longResult.truncated, true);
});
