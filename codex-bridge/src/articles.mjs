import { randomBytes } from 'node:crypto';
import { constants } from 'node:fs';
import { link, lstat, open, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { TextDecoder } from 'node:util';

import { atomicWrite } from './atomic.mjs';
import { LIMITS } from './limits.mjs';
import {
  assertContainedTarget,
  assertValidDate,
  resolveProjectRoot,
} from './paths.mjs';

const DRAFT_FIELD_MARKER = /^draft:[^\r\n]*(?=\r?$)/gmu;
const DATE_MARKER = /^date: (\d{4}-\d{2}-\d{2})(?=\r?$)/gmu;
const LASTMOD_MARKER = /^lastmod: (\d{4}-\d{2}-\d{2})(?=\r?$)/gmu;
const TOPIC_KEY_MARKER =
  /^topic_key: ([a-z0-9]+(?:-[a-z0-9]+)*)(?=\r?$)/gmu;
const LEDGER_RELATIVE_PATH = path.join('inputs', 'published-topics.md');
const UTF8_DECODER = new TextDecoder('utf-8', {
  fatal: true,
  ignoreBOM: true,
});

function assertValidSlug(slug) {
  if (
    typeof slug !== 'string' ||
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(slug)
  ) {
    throw new Error('Article slug must be canonical kebab-case without an extension');
  }
}

function assertOneDraftMarker(content, expected = 'draft: true') {
  const matches = content.match(DRAFT_FIELD_MARKER) ?? [];
  if (matches.length !== 1 || matches[0] !== expected) {
    throw new Error(
      `Article content must contain exactly one draft marker and it must be ${expected}`,
    );
  }
}

function parseFrontmatter(content) {
  const opening = /^(?:\uFEFF)?---\r?\n/u.exec(content);
  if (!opening) {
    throw new Error('Article must start with delimited YAML frontmatter');
  }
  const closing = /^---(?=\r?$)/gmu;
  closing.lastIndex = opening[0].length;
  const match = closing.exec(content);
  if (!match) {
    throw new Error('Article frontmatter must have a closing delimiter');
  }
  const closingLineEnd = content.indexOf('\n', match.index);
  return {
    raw: content.slice(opening[0].length, match.index),
    body: content.slice(
      closingLineEnd === -1 ? content.length : closingLineEnd + 1,
    ),
    start: opening[0].length,
    end: match.index,
  };
}

function replaceFrontmatter(content, frontmatter, replacement) {
  return `${content.slice(0, frontmatter.start)}${replacement}${content.slice(frontmatter.end)}`;
}

function assertRequiredBlock(content, pattern, label) {
  if ((content.match(pattern) ?? []).length !== 1) {
    throw new Error(
      `Article frontmatter must contain exactly one complete ${label}`,
    );
  }
}

function assertLanguageBlock(body, language) {
  const escaped = language.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const pattern = new RegExp(
    `<Lang value="${escaped}">\\r?\\n([\\s\\S]*?)\\r?\\n<\\/Lang>`,
    'gu',
  );
  const matches = [...body.matchAll(pattern)];
  if (matches.length !== 1 || matches[0][1].trim().length === 0) {
    throw new Error(
      `Article body must contain exactly one non-empty ${language} language block`,
    );
  }
  return matches[0].index;
}

function validateCompleteArticle(content, expectedDraft) {
  const frontmatter = parseFrontmatter(content);
  const normalized = frontmatter.raw.replaceAll('\r\n', '\n');
  assertOneDraftMarker(frontmatter.raw, `draft: ${expectedDraft}`);
  assertRequiredBlock(
    normalized,
    /^title:\n {2}en: .*\S.*\n {2}it: .*\S.*$/gmu,
    'bilingual title field',
  );
  assertRequiredBlock(
    normalized,
    /^summary:\n {2}en: >[+-]?\n(?: {4}.*\S.*\n)+ {2}it: >[+-]?\n(?: {4}.*\S.*(?:\n|$))+/gmu,
    'bilingual summary field',
  );
  assertRequiredBlock(
    normalized,
    /^tags:\n {2}- id: [a-z0-9]+(?:-[a-z0-9]+)*\n {4}label:\n {6}en: .*\S.*\n {6}it: .*\S.*(?=\n|$)/gmu,
    'bilingual tags field',
  );
  assertRequiredBlock(
    normalized,
    /^images:(?: \[\]|\n(?: {2}- .+(?:\n|$))+)(?=\n|$)/gmu,
    'images field',
  );

  const dateMatch = exactSingleMatch(frontmatter.raw, DATE_MARKER, 'date field');
  const lastmodMatch = exactSingleMatch(
    frontmatter.raw,
    LASTMOD_MARKER,
    'lastmod field',
  );
  const topicKeyMatch = exactSingleMatch(
    frontmatter.raw,
    TOPIC_KEY_MARKER,
    'canonical topic_key field',
  );
  assertValidDate(dateMatch[1]);
  assertValidDate(lastmodMatch[1]);

  const englishIndex = assertLanguageBlock(frontmatter.body, 'en');
  const italianIndex = assertLanguageBlock(frontmatter.body, 'it');
  if (englishIndex >= italianIndex) {
    throw new Error(
      'Article body must place the English block before the Italian block',
    );
  }
  return { frontmatter, topicKey: topicKeyMatch[1] };
}

function validateDraftArguments({ slug, content, overwrite }) {
  assertValidSlug(slug);
  if (typeof content !== 'string') {
    throw new Error('Article content must be a string');
  }
  if (typeof overwrite !== 'boolean') {
    throw new Error('Article overwrite approval must be explicit');
  }
  const frontmatter = parseFrontmatter(content);
  assertOneDraftMarker(frontmatter.raw);
}

async function readRegularUtf8(target, label) {
  const noFollow = constants.O_NOFOLLOW ?? 0;
  const handle = await open(target, constants.O_RDONLY | noFollow);
  try {
    const stat = await handle.stat();
    const targetStat = await lstat(target);
    if (
      targetStat.isSymbolicLink() ||
      targetStat.dev !== stat.dev ||
      targetStat.ino !== stat.ino
    ) {
      throw new Error(`${label} changed or became a symlink while opening`);
    }
    if (!stat.isFile()) {
      throw new Error(`${label} must be a regular file`);
    }
    if (stat.size > LIMITS.generatedFileBytes) {
      throw new Error(`${label} exceeds the generated-file size limit`);
    }

    const bytes = await handle.readFile();
    let content;
    try {
      content = UTF8_DECODER.decode(bytes);
    } catch (error) {
      throw new Error(`${label} must contain valid UTF-8`, { cause: error });
    }

    return {
      content,
      snapshot: {
        exists: true,
        dev: stat.dev,
        ino: stat.ino,
        isDirectory: false,
      },
    };
  } finally {
    await handle.close();
  }
}

async function readRegularArticle(target) {
  return readRegularUtf8(target, 'Article target');
}

async function optionalLstat(target) {
  try {
    return await lstat(target);
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return undefined;
    }
    throw error;
  }
}

function uniqueSibling(target, suffix) {
  return path.join(
    path.dirname(target),
    `.${path.basename(target)}.${process.pid}.${randomBytes(12).toString('hex')}.${suffix}`,
  );
}

function exactSingleMatch(content, pattern, label) {
  const matches = [...content.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`Article must contain exactly one ${label}`);
  }
  return matches[0];
}

function validateFinalizedArticle(content, publicationDate) {
  assertValidDate(publicationDate);
  const validated = validateCompleteArticle(content, false);
  const updatedFrontmatter = validated.frontmatter.raw.replace(
    LASTMOD_MARKER,
    `lastmod: ${publicationDate}`,
  );

  return {
    content: replaceFrontmatter(
      content,
      validated.frontmatter,
      updatedFrontmatter,
    ),
    topicKey: validated.topicKey,
  };
}

function ledgerEntry(topicKey, slug, publicationDate) {
  return `- ${topicKey} | ${slug} | published ${publicationDate}`;
}

function ledgerContainsTopicKey(content, topicKey) {
  return content.split(/\r?\n/u).some((line) => {
    const match = /^- ([a-z0-9]+(?:-[a-z0-9]+)*) \|/u.exec(line);
    return match?.[1] === topicKey;
  });
}

function updatedLedger(content, entry) {
  if (content === undefined || content.length === 0) {
    return `# Published topics\n\n${entry}\n`;
  }
  const separator = content.endsWith('\n') ? '' : '\n';
  return `${content}${separator}${entry}\n`;
}

export function createArticleOperations(options) {
  const context = {
    rootPromise: resolveProjectRoot(options.projectRoot),
    atomicWriteImpl: options.atomicWriteImpl ?? atomicWrite,
    beforePublishCommit: options.beforePublishCommit,
    beforeLedgerRename: options.beforeLedgerRename,
  };
  return {
    writeArticleDraft: (args) => writeArticleDraft(args, context),
    finalizeArticle: (args) => finalizeArticle(args, context),
    publishArticle: (args) => publishArticle(args, context),
  };
}

async function articleTarget(context, directory, slug) {
  assertValidSlug(slug);
  const root = await context.rootPromise;
  const relativeTarget = path.join(directory, `${slug}.mdx`);
  return assertContainedTarget(root, relativeTarget, {
    relativeDirectory: directory,
    extension: '.mdx',
  });
}

export async function writeArticleDraft(args, context) {
  validateDraftArguments(args);
  const target = await articleTarget(context, 'drafts', args.slug);
  await context.atomicWriteImpl(target, args.content, {
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: args.overwrite,
  });
  return { path: target };
}

export async function finalizeArticle({ slug }, context) {
  const target = await articleTarget(context, 'drafts', slug);
  const { content, snapshot } = await readRegularArticle(target);
  const validated = validateCompleteArticle(content, true);
  const finalized = replaceFrontmatter(
    content,
    validated.frontmatter,
    validated.frontmatter.raw.replace(DRAFT_FIELD_MARKER, 'draft: false'),
  );
  await context.atomicWriteImpl(target, finalized, {
    expectedTarget: snapshot,
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: true,
  });
  return { path: target };
}

async function ledgerTarget(context) {
  const root = await context.rootPromise;
  return assertContainedTarget(root, LEDGER_RELATIVE_PATH, {
    exactRelativePath: LEDGER_RELATIVE_PATH,
    extension: '.md',
  });
}

async function readLedger(target) {
  const stat = await optionalLstat(target);
  if (!stat) {
    return { exists: false, content: undefined };
  }
  const result = await readRegularUtf8(target, 'Published-topic ledger');
  return {
    exists: true,
    content: result.content,
    snapshot: result.snapshot,
  };
}

function sameFileSnapshot(left, right) {
  return (
    left.dev === right.dev &&
    left.ino === right.ino &&
    left.isDirectory === right.isDirectory
  );
}

async function assertArticleUnchanged(target, expectedContent, expectedSnapshot) {
  const current = await readRegularArticle(target);
  if (
    current.content !== expectedContent ||
    !sameFileSnapshot(current.snapshot, expectedSnapshot)
  ) {
    throw new Error('Validated article draft changed before publication move');
  }
}

async function assertLedgerUnchanged(target, expected) {
  const current = await readLedger(target);
  if (
    current.exists !== expected.exists ||
    current.content !== expected.content ||
    (current.exists && !sameFileSnapshot(current.snapshot, expected.snapshot))
  ) {
    throw new Error('Published-topic ledger changed before final rename');
  }
}

async function restoreLedger(target, prior, context) {
  if (!prior.exists) {
    await rm(target, { force: true });
    return;
  }
  await context.atomicWriteImpl(target, prior.content, {
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: true,
  });
}

async function cleanupFiles(targets) {
  const errors = [];
  for (const target of targets) {
    if (!target) {
      continue;
    }
    try {
      await rm(target, { force: true });
    } catch (error) {
      errors.push(error);
    }
  }
  return errors;
}

export async function publishArticle({ slug, publicationDate }, context) {
  assertValidSlug(slug);
  assertValidDate(publicationDate);

  const draft = await articleTarget(context, 'drafts', slug);
  const published = await articleTarget(context, 'published', slug);
  const ledger = await ledgerTarget(context);
  const publishedStat = await optionalLstat(published);
  if (publishedStat) {
    throw new Error('Published article already exists; publication collision refused');
  }

  const {
    content: draftContent,
    snapshot: draftSnapshot,
  } = await readRegularArticle(draft);
  const validated = validateFinalizedArticle(draftContent, publicationDate);
  const priorLedger = await readLedger(ledger);
  const ledgerUpdated = !ledgerContainsTopicKey(
    priorLedger.content ?? '',
    validated.topicKey,
  );
  const nextLedger = ledgerUpdated
    ? updatedLedger(
        priorLedger.content,
        ledgerEntry(validated.topicKey, slug, publicationDate),
      )
    : priorLedger.content;

  const articleStage = uniqueSibling(published, 'stage');
  const ledgerStage = ledgerUpdated ? uniqueSibling(ledger, 'stage') : undefined;
  const draftBackup = uniqueSibling(draft, 'backup');
  let backupMoved = false;
  let publishedMoved = false;
  let ledgerReplaced = false;

  try {
    await context.atomicWriteImpl(articleStage, validated.content, {
      maxBytes: LIMITS.generatedFileBytes,
      overwrite: false,
    });
    if (ledgerUpdated) {
      await context.atomicWriteImpl(ledgerStage, nextLedger, {
        maxBytes: LIMITS.generatedFileBytes,
        overwrite: false,
      });
    }

    await assertArticleUnchanged(draft, draftContent, draftSnapshot);
    await rename(draft, draftBackup);
    backupMoved = true;

    await articleTarget(context, 'published', slug);
    if (await optionalLstat(published)) {
      throw new Error('Published article target changed before final rename');
    }
    await context.beforePublishCommit?.({ published, articleStage });
    try {
      await link(articleStage, published);
    } catch (error) {
      if (error?.code === 'EEXIST') {
        throw new Error('Published article collision at commit boundary', {
          cause: error,
        });
      }
      throw error;
    }
    publishedMoved = true;
    await rm(articleStage);

    if (ledgerUpdated) {
      await ledgerTarget(context);
      await context.beforeLedgerRename?.({ ledger, ledgerStage, published });
      await assertLedgerUnchanged(ledger, priorLedger);
      await rename(ledgerStage, ledger);
      ledgerReplaced = true;
    }

    await rm(draftBackup);
    backupMoved = false;
    return { publishedPath: published, ledgerUpdated };
  } catch (error) {
    const rollbackErrors = [];
    if (ledgerReplaced) {
      try {
        await restoreLedger(ledger, priorLedger, context);
      } catch (rollbackError) {
        rollbackErrors.push(rollbackError);
      }
    }
    if (publishedMoved) {
      try {
        await rm(published, { force: true });
        publishedMoved = false;
      } catch (rollbackError) {
        rollbackErrors.push(rollbackError);
      }
    }
    if (backupMoved) {
      try {
        await rename(draftBackup, draft);
        backupMoved = false;
      } catch (rollbackError) {
        rollbackErrors.push(rollbackError);
      }
    }
    rollbackErrors.push(
      ...(await cleanupFiles([articleStage, ledgerStage, draftBackup])),
    );

    if (rollbackErrors.length > 0) {
      const failure = new AggregateError(
        [error, ...rollbackErrors],
        'Article publication failed and rollback could not fully restore state',
      );
      failure.code = 'publication_rollback_incomplete';
      throw failure;
    }
    const failure = new Error(
      'Article publication failed; prior state was restored',
      { cause: error },
    );
    failure.code = 'publication_failed_restored';
    throw failure;
  }
}
