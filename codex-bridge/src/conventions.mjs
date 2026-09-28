import path from 'node:path';

import { atomicWrite } from './atomic.mjs';
import { LIMITS } from './limits.mjs';
import { assertContainedTarget, resolveProjectRoot } from './paths.mjs';

export function createConventionOperations(options) {
  const context = {
    rootPromise: resolveProjectRoot(options.projectRoot),
    atomicWriteImpl: options.atomicWriteImpl ?? atomicWrite,
  };
  return {
    writeConventions: (args) => writeConventions(args, context),
  };
}

export async function writeConventions({ content, overwrite }, context) {
  if (typeof content !== 'string' || content.trim().length === 0) {
    throw new Error('Convention content must be non-empty');
  }
  if (typeof overwrite !== 'boolean') {
    throw new Error('Convention overwrite approval must be explicit');
  }

  const root = await context.rootPromise;
  const target = await assertContainedTarget(root, 'CONVENTIONS.md', {
    exactRelativePath: 'CONVENTIONS.md',
    extension: '.md',
  });
  await context.atomicWriteImpl(target, content, {
    maxBytes: LIMITS.generatedFileBytes,
    overwrite,
  });
  return { path: target };
}
