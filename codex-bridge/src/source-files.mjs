import { constants } from 'node:fs';
import { lstat, open, realpath } from 'node:fs/promises';
import path from 'node:path';
import { TextDecoder } from 'node:util';

import { LIMITS } from './limits.mjs';
import { assertContainedTarget, resolveProjectRoot } from './paths.mjs';

const READ_CHUNK_BYTES = 64 * 1024;

function isContained(root, target) {
  const relative = path.relative(root, target);
  return (
    relative === '' ||
    (!path.isAbsolute(relative) &&
      relative !== '..' &&
      !relative.startsWith(`..${path.sep}`))
  );
}

async function resolveConfirmedRoots(confirmedProjects) {
  if (!Array.isArray(confirmedProjects) || confirmedProjects.length === 0) {
    throw new Error('At least one confirmed project is required');
  }

  return Promise.all(
    confirmedProjects.map(async (project) => {
      if (typeof project !== 'string' || !path.isAbsolute(project)) {
        throw new Error('Confirmed project paths must be absolute');
      }
      return {
        supplied: path.resolve(project),
        real: await resolveProjectRoot(project),
      };
    }),
  );
}

async function resolveAllowedTarget(requestedPath, roots) {
  for (const root of roots) {
    if (path.resolve(requestedPath) === root.supplied) {
      throw new Error('Source target must be a regular file, not a directory');
    }
    try {
      return await assertContainedTarget(root.supplied, requestedPath);
    } catch {
      // A later confirmed root may contain the requested path.
    }
  }
  throw new Error('Source target is outside the confirmed projects');
}

async function readBoundedText(handle, fileSize) {
  const decoder = new TextDecoder('utf-8', {
    fatal: true,
    ignoreBOM: true,
  });
  const buffer = Buffer.alloc(Math.min(READ_CHUNK_BYTES, fileSize || 1));
  let position = 0;
  let codePointsSeen = 0;
  const retainedCodePoints = [];
  function consume(decoded) {
    for (const codePoint of decoded) {
      codePointsSeen += 1;
      if (retainedCodePoints.length < LIMITS.sourceFileCharacters) {
        retainedCodePoints.push(codePoint);
      }
    }
  }
  try {
    while (position < fileSize) {
      const length = Math.min(buffer.length, fileSize - position);
      const { bytesRead } = await handle.read(buffer, 0, length, position);
      if (bytesRead === 0) {
        throw new Error('Source target changed while reading');
      }
      const bytes = buffer.subarray(0, bytesRead);
      if (bytes.includes(0)) {
        throw new Error(
          'Source target must contain UTF-8 text, not binary content',
        );
      }
      const decoded = decoder.decode(bytes, { stream: true });
      consume(decoded);
      position += bytesRead;
    }

    consume(decoder.decode());
  } catch (error) {
    if (error?.message?.includes('binary content')) {
      throw error;
    }
    throw new Error('Source target must contain valid UTF-8 text', {
      cause: error,
    });
  }

  return {
    text: retainedCodePoints.join(''),
    truncated: codePointsSeen > LIMITS.sourceFileCharacters,
  };
}

export async function readSourceFile({ path: requestedPath, confirmedProjects }) {
  if (typeof requestedPath !== 'string' || !path.isAbsolute(requestedPath)) {
    throw new Error('Source path must be absolute');
  }

  const roots = await resolveConfirmedRoots(confirmedProjects);
  const target = await resolveAllowedTarget(requestedPath, roots);
  const targetRealBefore = await realpath(target);
  if (!roots.some((root) => isContained(root.real, targetRealBefore))) {
    throw new Error('Source target real path is outside the confirmed projects');
  }

  const noFollow = constants.O_NOFOLLOW ?? 0;
  const handle = await open(target, constants.O_RDONLY | noFollow);
  try {
    const stat = await handle.stat();
    const targetStat = await lstat(target);
    const targetRealAfter = await realpath(target);
    if (
      targetStat.isSymbolicLink() ||
      targetStat.dev !== stat.dev ||
      targetStat.ino !== stat.ino ||
      targetRealBefore !== targetRealAfter ||
      !roots.some((root) => isContained(root.real, targetRealAfter))
    ) {
      throw new Error('Source target changed, escaped, or became a symlink');
    }
    if (!stat.isFile()) {
      throw new Error('Source target must be a regular file');
    }
    if (stat.size > LIMITS.sourceFileBytes) {
      throw new Error('Source target exceeds the source-file byte limit');
    }

    const result = await readBoundedText(handle, stat.size);
    const statAfter = await handle.stat();
    const targetStatAfter = await lstat(target);
    const targetRealFinal = await realpath(target);
    if (
      statAfter.dev !== stat.dev ||
      statAfter.ino !== stat.ino ||
      statAfter.size !== stat.size ||
      targetStatAfter.isSymbolicLink() ||
      targetStatAfter.dev !== stat.dev ||
      targetStatAfter.ino !== stat.ino ||
      targetRealFinal !== targetRealBefore ||
      !roots.some((root) => isContained(root.real, targetRealFinal))
    ) {
      throw new Error('Source target changed, escaped, or became a symlink');
    }

    return {
      path: targetRealFinal,
      ...result,
    };
  } finally {
    await handle.close();
  }
}
