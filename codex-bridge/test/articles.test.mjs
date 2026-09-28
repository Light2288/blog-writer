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

import { atomicWrite } from '../src/atomic.mjs';
import { createArticleOperations } from '../src/articles.mjs';
import { createWriterHandlers } from '../src/tools/writer.mjs';

const SLUG = 'bounded-article';
const DRAFT = [
  '---',
  'title: Bounded article',
  'date: 2026-09-01',
  'lastmod: 2026-09-01',
  'topic_key: bounded-topic',
  'draft: true',
  '---',
  '',
  '<Lang value="en">',
  '',
  'Evidence.',
  '',
  '</Lang>',
  '',
].join('\n');

async function temporaryProject(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'blog-writer-articles-'));
  await Promise.all(
    ['drafts', 'published', 'inputs'].map((directory) =>
      mkdir(path.join(root, directory)),
    ),
  );
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

function draftTarget(root, slug = SLUG) {
  return path.join(root, 'drafts', `${slug}.mdx`);
}

function publishedTarget(root, slug = SLUG) {
  return path.join(root, 'published', `${slug}.mdx`);
}

function ledgerTarget(root) {
  return path.join(root, 'inputs', 'published-topics.md');
}

async function projectState(root) {
  const state = {};
  for (const directory of ['drafts', 'published', 'inputs']) {
    const names = (await readdir(path.join(root, directory))).sort();
    state[directory] = await Promise.all(
      names.map(async (name) => [
        name,
        await readFile(path.join(root, directory, name)),
      ]),
    );
  }
  return state;
}

test('writeArticleDraft_writes_only_a_canonical_kebab_slug_in_drafts', async (t) => {
  const root = await temporaryProject(t);
  const operations = createArticleOperations({ projectRoot: root });

  const result = await operations.writeArticleDraft({
    slug: SLUG,
    content: DRAFT,
    overwrite: false,
  });

  assert.equal(result.path, await realpath(draftTarget(root)));
  assert.equal(await readFile(draftTarget(root), 'utf8'), DRAFT);
  assert.deepEqual(await readdir(path.join(root, 'published')), []);
  assert.deepEqual(await readdir(path.join(root, 'inputs')), []);

  const before = await projectState(root);
  for (const slug of [
    '../escape',
    'nested/article',
    'Article-Title',
    'article--title',
    '-article',
    'article-',
    'article.mdx',
    '',
  ]) {
    await assert.rejects(
      operations.writeArticleDraft({
        slug,
        content: DRAFT,
        overwrite: true,
      }),
      /slug|kebab|mdx|path/i,
    );
    assert.deepEqual(await projectState(root), before);
  }
});

test('writeArticleDraft_requires_exactly_one_draft_true_marker', async (t) => {
  const root = await temporaryProject(t);
  const operations = createArticleOperations({ projectRoot: root });
  const invalidContents = [
    DRAFT.replace('draft: true\n', ''),
    DRAFT.replace('draft: true', 'draft: false'),
    DRAFT.replace('draft: true', ' draft: true'),
    DRAFT.replace('draft: true', 'draft: true\ndraft: true'),
  ];

  for (const content of invalidContents) {
    await assert.rejects(
      operations.writeArticleDraft({
        slug: SLUG,
        content,
        overwrite: false,
      }),
      /exactly one.*draft: true/i,
    );
    assert.deepEqual(await readdir(path.join(root, 'drafts')), []);
  }
});

test('writeArticleDraft_requires_explicit_collision_approval_and_enforces_size', async (t) => {
  const root = await temporaryProject(t);
  const operations = createArticleOperations({ projectRoot: root });
  await writeFile(draftTarget(root), DRAFT);
  const replacement = DRAFT.replace('Evidence.', 'Revised evidence.');

  await assert.rejects(
    operations.writeArticleDraft({
      slug: SLUG,
      content: replacement,
      overwrite: false,
    }),
    /overwrite|exists|collision/i,
  );
  assert.equal(await readFile(draftTarget(root), 'utf8'), DRAFT);

  await operations.writeArticleDraft({
    slug: SLUG,
    content: replacement,
    overwrite: true,
  });
  assert.equal(await readFile(draftTarget(root), 'utf8'), replacement);

  const oversized = `${DRAFT}${'x'.repeat(1_048_576)}`;
  await assert.rejects(
    operations.writeArticleDraft({
      slug: 'oversized-article',
      content: oversized,
      overwrite: false,
    }),
    /limit|1[ ,]?048[ ,]?576|size/i,
  );
  await assert.rejects(readFile(draftTarget(root, 'oversized-article')), {
    code: 'ENOENT',
  });
});

test('writeArticleDraft_rejects_a_symlink_target_without_touching_its_destination', async (t) => {
  const root = await temporaryProject(t);
  const outside = await mkdtemp(path.join(tmpdir(), 'blog-writer-article-outside-'));
  t.after(() => rm(outside, { recursive: true, force: true }));
  const outsideTarget = path.join(outside, 'outside.mdx');
  await writeFile(outsideTarget, 'outside\n');
  await symlink(outsideTarget, draftTarget(root));
  const operations = createArticleOperations({ projectRoot: root });

  await assert.rejects(
    operations.writeArticleDraft({
      slug: SLUG,
      content: DRAFT,
      overwrite: true,
    }),
    /symlink/i,
  );
  assert.equal(await readFile(outsideTarget, 'utf8'), 'outside\n');
});

test('finalizeArticle_changes_only_the_single_draft_marker', async (t) => {
  const root = await temporaryProject(t);
  const operations = createArticleOperations({ projectRoot: root });
  const draft = `\uFEFF${DRAFT.replaceAll('\n', '\r\n')}Body says draft: true inline.\r\n`;
  await operations.writeArticleDraft({
    slug: SLUG,
    content: draft,
    overwrite: false,
  });

  const result = await operations.finalizeArticle({ slug: SLUG });
  const finalized = await readFile(draftTarget(root), 'utf8');

  assert.equal(result.path, await realpath(draftTarget(root)));
  assert.equal(finalized, draft.replace('draft: true', 'draft: false'));
  assert.equal(finalized.replace('draft: false', 'draft: true'), draft);
});

test('finalizeArticle_rejects_missing_duplicate_already_final_and_invalid_UTF_8', async (t) => {
  const cases = [
    Buffer.from(DRAFT.replace('draft: true\n', '')),
    Buffer.from(DRAFT.replace('draft: true', 'draft: true\ndraft: true')),
    Buffer.from(DRAFT.replace('draft: true', 'draft: false')),
    Buffer.concat([
      Buffer.from(DRAFT),
      Buffer.from([0xff]),
    ]),
  ];

  for (const content of cases) {
    await t.test(`case-${cases.indexOf(content)}`, async (subtest) => {
      const root = await temporaryProject(subtest);
      await writeFile(draftTarget(root), content);
      const operations = createArticleOperations({ projectRoot: root });
      const before = await projectState(root);

      await assert.rejects(
        operations.finalizeArticle({ slug: SLUG }),
        /exactly one.*draft: true|UTF-?8|encoding/i,
      );
      assert.deepEqual(await projectState(root), before);
    });
  }
});

test('finalizeArticle_rejects_conflicting_or_invalid_additional_draft_markers_without_changes', async (t) => {
  const cases = [
    DRAFT.replace('draft: true', 'draft: true\ndraft: false'),
    DRAFT.replace('draft: true', 'draft: true\ndraft: maybe'),
  ];

  for (const [index, content] of cases.entries()) {
    await t.test(`case-${index}`, async (subtest) => {
      const root = await temporaryProject(subtest);
      await writeFile(draftTarget(root), content);
      const before = await readFile(draftTarget(root));
      const operations = createArticleOperations({ projectRoot: root });

      await assert.rejects(
        operations.finalizeArticle({ slug: SLUG }),
        /exactly one.*draft|draft marker/i,
      );
      assert.deepEqual(await readFile(draftTarget(root)), before);
      assert.deepEqual(await readdir(path.join(root, 'drafts')), [
        'bounded-article.mdx',
      ]);
    });
  }
});

test('createWriterHandlers_exposes_only_scoped_writer_tools_and_arguments', async (t) => {
  const root = await temporaryProject(t);
  const handlers = createWriterHandlers({ projectRoot: root });

  assert.deepEqual(Object.keys(handlers), [
    'read_source_file',
    'write_article_draft',
    'finalize_article',
    'publish_article',
  ]);
  assert.deepEqual(
    Object.keys(handlers.read_source_file.config.inputSchema.shape).sort(),
    ['confirmed_projects', 'path'],
  );
  assert.deepEqual(
    Object.keys(handlers.write_article_draft.config.inputSchema.shape).sort(),
    ['content', 'overwrite', 'slug'],
  );
  assert.deepEqual(
    Object.keys(handlers.finalize_article.config.inputSchema.shape),
    ['slug'],
  );
  assert.deepEqual(
    Object.keys(handlers.publish_article.config.inputSchema.shape).sort(),
    ['publication_date', 'slug'],
  );
});

test('publishArticle_validates_final_marker_date_and_frontmatter_before_mutation', async (t) => {
  const root = await temporaryProject(t);
  const operations = createArticleOperations({ projectRoot: root });
  await writeFile(draftTarget(root), DRAFT);
  const beforeDraft = await readFile(draftTarget(root));

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /draft: false|finalized/i,
  );
  assert.deepEqual(await readFile(draftTarget(root)), beforeDraft);

  await writeFile(draftTarget(root), DRAFT.replace('draft: true', 'draft: false'));
  for (const publicationDate of ['2026-9-28', '2026-02-29', '../escape']) {
    const before = await projectState(root);
    await assert.rejects(
      operations.publishArticle({ slug: SLUG, publicationDate }),
      /date|YYYY-MM-DD/i,
    );
    assert.deepEqual(await projectState(root), before);
  }

  const malformed = DRAFT.replace('draft: true', 'draft: false').replace(
    'lastmod: 2026-09-01',
    'lastmod: 2026-09-01\nlastmod: 2026-09-02',
  );
  await writeFile(draftTarget(root), malformed);
  const beforeMalformed = await projectState(root);
  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /exactly one.*lastmod/i,
  );
  assert.deepEqual(await projectState(root), beforeMalformed);
});

test('publishArticle_moves_only_the_requested_finalized_article_and_updates_metadata', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const other = finalized
    .replace('bounded-topic', 'other-topic')
    .replace('Bounded article', 'Other article');
  await writeFile(draftTarget(root), finalized);
  await writeFile(draftTarget(root, 'other-article'), other);
  const operations = createArticleOperations({ projectRoot: root });

  const result = await operations.publishArticle({
    slug: SLUG,
    publicationDate: '2026-09-28',
  });

  const published = await readFile(publishedTarget(root), 'utf8');
  assert.deepEqual(result, {
    publishedPath: await realpath(publishedTarget(root)),
    ledgerUpdated: true,
  });
  assert.match(published, /^date: 2026-09-01$/mu);
  assert.equal((published.match(/^date:/gmu) ?? []).length, 1);
  assert.match(published, /^lastmod: 2026-09-28$/mu);
  assert.equal((published.match(/^lastmod:/gmu) ?? []).length, 1);
  assert.match(published, /^draft: false$/mu);
  assert.equal(await readFile(draftTarget(root, 'other-article'), 'utf8'), other);
  await assert.rejects(readFile(draftTarget(root)), { code: 'ENOENT' });
  assert.equal(
    await readFile(ledgerTarget(root), 'utf8'),
    '# Published topics\n\n- bounded-topic | bounded-article | published 2026-09-28\n',
  );
  assert.deepEqual((await readdir(path.join(root, 'drafts'))).sort(), [
    'other-article.mdx',
  ]);
  assert.deepEqual(await readdir(path.join(root, 'published')), [
    'bounded-article.mdx',
  ]);
  assert.deepEqual(await readdir(path.join(root, 'inputs')), [
    'published-topics.md',
  ]);
});

test('publishArticle_rejects_a_published_collision_before_moving_the_draft', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  await writeFile(draftTarget(root), finalized);
  await writeFile(publishedTarget(root), 'existing published bytes\n');
  const operations = createArticleOperations({ projectRoot: root });
  const before = await projectState(root);

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /published.*exists|collision|overwrite/i,
  );
  assert.deepEqual(await projectState(root), before);
});

test('publishArticle_does_not_clobber_a_destination_created_at_commit_boundary', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const ledger = '# Published topics\n\n- prior-topic | prior-article | published 2026-09-20\n';
  const competitor = 'competitor published bytes\n';
  await writeFile(draftTarget(root), finalized);
  await writeFile(ledgerTarget(root), ledger);
  let hookCalls = 0;
  const operations = createArticleOperations({
    projectRoot: root,
    beforePublishCommit: async ({ published }) => {
      hookCalls += 1;
      await writeFile(published, competitor, { flag: 'wx' });
    },
  });

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /collision|exists|publication failed/i,
  );

  assert.equal(hookCalls, 1);
  assert.equal(await readFile(publishedTarget(root), 'utf8'), competitor);
  assert.equal(await readFile(draftTarget(root), 'utf8'), finalized);
  assert.equal(await readFile(ledgerTarget(root), 'utf8'), ledger);
  assert.deepEqual(await readdir(path.join(root, 'drafts')), [
    'bounded-article.mdx',
  ]);
  assert.deepEqual(await readdir(path.join(root, 'published')), [
    'bounded-article.mdx',
  ]);
  assert.deepEqual(await readdir(path.join(root, 'inputs')), [
    'published-topics.md',
  ]);
});

test('publishArticle_does_not_move_a_draft_replaced_after_validation', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const replacement = finalized.replace('Evidence.', 'Tampered.');
  await writeFile(draftTarget(root), finalized);
  let replaced = false;
  const operations = createArticleOperations({
    projectRoot: root,
    atomicWriteImpl: async (target, content, options) => {
      await atomicWrite(target, content, options);
      if (
        !replaced &&
        path.dirname(target) === path.join(await realpath(root), 'published')
      ) {
        replaced = true;
        await writeFile(draftTarget(root), replacement);
      }
    },
  });

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /changed|replacement|publication failed/i,
  );

  assert.equal(replaced, true);
  assert.equal(await readFile(draftTarget(root), 'utf8'), replacement);
  await assert.rejects(readFile(publishedTarget(root)), { code: 'ENOENT' });
  assert.deepEqual(await readdir(path.join(root, 'inputs')), []);
  assert.deepEqual(await readdir(path.join(root, 'published')), []);
});

test('publishArticle_is_ledger_idempotent_by_topic_key', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const ledger = [
    '# Published topics',
    '',
    '- bounded-topic | earlier-article | published 2026-09-20',
    '- another-topic | another-article | published 2026-09-21',
    '',
  ].join('\n');
  await writeFile(draftTarget(root), finalized);
  await writeFile(ledgerTarget(root), ledger);
  const operations = createArticleOperations({ projectRoot: root });

  const result = await operations.publishArticle({
    slug: SLUG,
    publicationDate: '2026-09-28',
  });

  assert.equal(result.ledgerUpdated, false);
  assert.equal(await readFile(ledgerTarget(root), 'utf8'), ledger);
  assert.equal(
    (ledger.match(/^- bounded-topic \|/gmu) ?? []).length,
    1,
  );
  assert.equal(
    await readFile(publishedTarget(root), 'utf8'),
    finalized.replace('lastmod: 2026-09-01', 'lastmod: 2026-09-28'),
  );
});

test('publishArticle_appends_without_rewriting_existing_ledger_bytes', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const ledger = [
    '# Published topics',
    '',
    '- prior-topic | prior-article | published 2026-09-20  ',
    '',
    '',
  ].join('\n');
  await writeFile(draftTarget(root), finalized);
  await writeFile(ledgerTarget(root), ledger);
  const operations = createArticleOperations({ projectRoot: root });

  await operations.publishArticle({
    slug: SLUG,
    publicationDate: '2026-09-28',
  });

  assert.equal(
    await readFile(ledgerTarget(root), 'utf8'),
    `${ledger}- bounded-topic | bounded-article | published 2026-09-28\n`,
  );
});

test('publishArticle_does_not_overwrite_a_ledger_replaced_before_final_rename', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const priorLedger = '# Published topics\n\n- prior-topic | prior-article | published 2026-09-20\n';
  const replacementLedger = '# Published topics\n\n- concurrent-topic | concurrent-article | published 2026-09-27\n';
  await writeFile(draftTarget(root), finalized);
  await writeFile(ledgerTarget(root), priorLedger);
  const operations = createArticleOperations({
    projectRoot: root,
    beforeLedgerRename: async () => {
      await writeFile(ledgerTarget(root), replacementLedger);
    },
  });

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /ledger.*changed|publication failed/i,
  );

  assert.equal(await readFile(draftTarget(root), 'utf8'), finalized);
  assert.equal(await readFile(ledgerTarget(root), 'utf8'), replacementLedger);
  await assert.rejects(readFile(publishedTarget(root)), { code: 'ENOENT' });
  assert.deepEqual(await readdir(path.join(root, 'published')), []);
});

test('publishArticle_restores_draft_ledger_and_no_published_duplicate_after_post_move_failure', async (t) => {
  const root = await temporaryProject(t);
  const finalized = DRAFT.replace('draft: true', 'draft: false');
  const ledger = '# Published topics\n\n- prior-topic | prior-article | published 2026-09-20\n';
  await writeFile(draftTarget(root), finalized);
  await writeFile(ledgerTarget(root), ledger);
  const before = await projectState(root);
  let hookCalls = 0;
  const operations = createArticleOperations({
    projectRoot: root,
    beforeLedgerRename: async () => {
      hookCalls += 1;
      throw new Error('injected ledger replacement failure');
    },
  });

  await assert.rejects(
    operations.publishArticle({
      slug: SLUG,
      publicationDate: '2026-09-28',
    }),
    /publish.*failed.*restored|restor/i,
  );

  assert.equal(hookCalls, 1);
  assert.deepEqual(await projectState(root), before);
  await assert.rejects(readFile(publishedTarget(root)), { code: 'ENOENT' });
});
