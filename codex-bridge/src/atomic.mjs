import { randomBytes } from 'node:crypto';
import {
  lstat,
  open,
  realpath,
  rename,
  rm,
} from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_FS_OPS = Object.freeze({ lstat, open, realpath, rename, rm });

async function snapshot(target, fsOps) {
  try {
    const stat = await fsOps.lstat(target);
    if (stat.isSymbolicLink()) {
      throw new Error('Atomic target must not be a symlink');
    }
    return {
      exists: true,
      dev: stat.dev,
      ino: stat.ino,
      isDirectory: stat.isDirectory(),
    };
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return { exists: false };
    }
    throw error;
  }
}

function sameSnapshot(before, after) {
  if (before.exists !== after.exists) {
    return false;
  }
  return (
    !before.exists ||
    (before.dev === after.dev &&
      before.ino === after.ino &&
      before.isDirectory === after.isDirectory)
  );
}

export async function atomicWrite(target, content, options = {}) {
  if (typeof target !== 'string' || !path.isAbsolute(target)) {
    throw new Error('Atomic target must be an absolute path');
  }
  if (typeof content !== 'string') {
    throw new Error('Atomic content must be a string');
  }

  const maxBytes = options.maxBytes ?? Number.POSITIVE_INFINITY;
  if (Buffer.byteLength(content, 'utf8') > maxBytes) {
    throw new Error(`Generated content exceeds the ${maxBytes}-byte limit`);
  }

  const fsOps = { ...DEFAULT_FS_OPS, ...(options.fsOps ?? {}) };
  const parent = path.dirname(target);
  const parentBefore = await snapshot(parent, fsOps);
  if (!parentBefore.exists || !parentBefore.isDirectory) {
    throw new Error('Atomic target parent must be an existing directory');
  }
  const parentRealBefore = await fsOps.realpath(parent);
  const targetBefore = await snapshot(target, fsOps);
  if (
    options.expectedTarget !== undefined &&
    !sameSnapshot(options.expectedTarget, targetBefore)
  ) {
    throw new Error('Atomic target changed before write');
  }
  if (targetBefore.exists && targetBefore.isDirectory) {
    throw new Error('Atomic target must be a file');
  }
  if (targetBefore.exists && options.overwrite !== true) {
    throw new Error('Target already exists; explicit overwrite approval is required');
  }

  const temporary = path.join(
    parent,
    `.${path.basename(target)}.${process.pid}.${randomBytes(12).toString('hex')}.tmp`,
  );
  let temporaryCreated = false;

  try {
    const handle = await fsOps.open(temporary, 'wx', 0o600);
    temporaryCreated = true;
    try {
      await handle.writeFile(content, 'utf8');
      await handle.sync();
    } finally {
      await handle.close();
    }

    await options.beforeRename?.({ target, temporary });

    const parentAfter = await snapshot(parent, fsOps);
    const targetAfter = await snapshot(target, fsOps);
    const parentRealAfter = await fsOps.realpath(parent);
    if (
      !sameSnapshot(parentBefore, parentAfter) ||
      parentRealBefore !== parentRealAfter
    ) {
      throw new Error('Atomic target parent changed before rename');
    }
    if (!sameSnapshot(targetBefore, targetAfter)) {
      throw new Error('Atomic target changed before rename');
    }

    await fsOps.rename(temporary, target);
    temporaryCreated = false;
  } catch (error) {
    if (temporaryCreated) {
      try {
        await fsOps.rm(temporary, { force: true });
      } catch (cleanupError) {
        throw new AggregateError(
          [error, cleanupError],
          'Atomic write failed and its temporary file could not be removed',
        );
      }
    }
    throw error;
  }
}
