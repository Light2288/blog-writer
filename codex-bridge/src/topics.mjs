import { constants } from 'node:fs';
import { lstat, open } from 'node:fs/promises';
import path from 'node:path';
import { TextDecoder } from 'node:util';

import { atomicWrite } from './atomic.mjs';
import { LIMITS } from './limits.mjs';
import {
  assertContainedTarget,
  assertValidDate,
  resolveProjectRoot,
} from './paths.mjs';

const DRAFT_STATUS_ROW =
  /^(\|[ \t]*Status[ \t]*\|[ \t]*)DRAFT([ \t]*\|[ \t]*)(?=\r?$)/gmu;
const STATUS_DECLARATION =
  /^(?:\|[ \t]*Status[ \t]*\|[^\r\n]*|[ \t]*Status[ \t]*:[^\r\n]*)(?=\r?$)/gmu;
const UTF8_DECODER = new TextDecoder('utf-8', {
  fatal: true,
  ignoreBOM: true,
});

function assertOneDraftStatusRow(content) {
  const draftRows = content.match(DRAFT_STATUS_ROW) ?? [];
  const statusDeclarations = content.match(STATUS_DECLARATION) ?? [];
  if (draftRows.length !== 1 || statusDeclarations.length !== 1) {
    throw new Error('Topic content must contain exactly one DRAFT status row');
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
  assertOneDraftStatusRow(content);
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
    const bytes = await handle.readFile();
    let content;
    try {
      content = UTF8_DECODER.decode(bytes);
    } catch (error) {
      throw new Error('Topic file must contain valid UTF-8', { cause: error });
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
  assertOneDraftStatusRow(content);
  const finalized = content.replace(DRAFT_STATUS_ROW, '$1FINAL$2');
  await context.atomicWriteImpl(target, finalized, {
    expectedTarget: snapshot,
    maxBytes: LIMITS.generatedFileBytes,
    overwrite: true,
  });
  return { path: target };
}
