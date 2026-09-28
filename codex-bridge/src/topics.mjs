import { constants } from 'node:fs';
import { lstat, open } from 'node:fs/promises';
import path from 'node:path';

import { atomicWrite } from './atomic.mjs';
import { LIMITS } from './limits.mjs';
import {
  assertContainedTarget,
  assertValidDate,
  resolveProjectRoot,
} from './paths.mjs';

const DRAFT_MARKER = /^Status: DRAFT(?=\r?$)/gmu;

function assertOneDraftMarker(content) {
  const matches = content.match(DRAFT_MARKER) ?? [];
  if (matches.length !== 1) {
    throw new Error('Topic content must contain exactly one Status: DRAFT marker');
  }
}

function validateWriteArguments({ date, content, overwrite }) {
  assertValidDate(date);
  if (typeof content !== 'string') {
    throw new Error('Topic content must be a string');
  }
  if (typeof overwrite !== 'boolean') {
    throw new Error('Topic overwrite approval must be explicit');
  }
  assertOneDraftMarker(content);
}

async function readRegularFile(target) {
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
      throw new Error('Topic target changed or became a symlink while opening');
    }
    if (!stat.isFile()) {
      throw new Error('Topic target must be a regular file');
    }
    if (stat.size > LIMITS.generatedFileBytes) {
      throw new Error('Topic file exceeds the generated-file size limit');
    }
    return {
      content: await handle.readFile('utf8'),
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

export function createTopicOperations(options) {
  const context = {
    rootPromise: resolveProjectRoot(options.projectRoot),
    atomicWriteImpl: options.atomicWriteImpl ?? atomicWrite,
  };
  return {
    writeTopicDraft: (args) => writeTopicDraft(args, context),
    finalizeTopics: (args) => finalizeTopics(args, context),
  };
}

async function topicTarget(context, date) {
  assertValidDate(date);
  const root = await context.rootPromise;
  const relativeTarget = path.join('inputs', `topics-${date}.md`);
  return assertContainedTarget(root, relativeTarget, {
    exactRelativePath: relativeTarget,
    extension: '.md',
  });
}

export async function writeTopicDraft(args, context) {
  validateWriteArguments(args);
  const target = await topicTarget(context, args.date);
  await context.atomicWriteImpl(target, args.content, {
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: args.overwrite,
  });
  return { path: target };
}

export async function finalizeTopics({ date }, context) {
  const target = await topicTarget(context, date);
  const { content, snapshot } = await readRegularFile(target);
  assertOneDraftMarker(content);
  const finalized = content.replace(DRAFT_MARKER, 'Status: FINAL');
  await context.atomicWriteImpl(target, finalized, {
    expectedTarget: snapshot,
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: true,
  });
  return { path: target };
}
