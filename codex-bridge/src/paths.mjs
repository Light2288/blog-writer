import { lstat, realpath } from 'node:fs/promises';
import path from 'node:path';

function isContained(relativePath) {
  return (
    relativePath === '' ||
    (!path.isAbsolute(relativePath) &&
      relativePath !== '..' &&
      !relativePath.startsWith(`..${path.sep}`))
  );
}

function hasTraversal(target) {
  return target.split(/[\\/]+/u).includes('..');
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

export function assertValidDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    throw new Error('Invalid date: expected YYYY-MM-DD');
  }

  const [year, month, day] = value.split('-').map(Number);
  const candidate = new Date(Date.UTC(year, month - 1, day));
  if (
    candidate.getUTCFullYear() !== year ||
    candidate.getUTCMonth() !== month - 1 ||
    candidate.getUTCDate() !== day
  ) {
    throw new Error('Invalid calendar date');
  }

  return value;
}

export async function resolveProjectRoot(root) {
  if (typeof root !== 'string' || !path.isAbsolute(root)) {
    throw new Error('Project root must be an absolute path');
  }

  const rootPath = await realpath(root);
  const rootStat = await lstat(rootPath);
  if (!rootStat.isDirectory()) {
    throw new Error('Project root must be a directory');
  }
  return rootPath;
}

export async function assertContainedTarget(root, target, policy = {}) {
  if (typeof target !== 'string' || target.length === 0) {
    throw new Error('Target path is required');
  }
  if (hasTraversal(target)) {
    throw new Error('Target path traversal is not allowed');
  }

  const suppliedRoot = path.resolve(root);
  const canonicalRoot = await resolveProjectRoot(suppliedRoot);
  const absoluteTarget = path.isAbsolute(target)
    ? path.resolve(target)
    : path.resolve(suppliedRoot, target);

  let relativeTarget = path.relative(suppliedRoot, absoluteTarget);
  if (!isContained(relativeTarget)) {
    relativeTarget = path.relative(canonicalRoot, absoluteTarget);
  }
  if (!isContained(relativeTarget) || relativeTarget === '') {
    throw new Error('Target is outside the project root');
  }

  const canonicalTarget = path.resolve(canonicalRoot, relativeTarget);
  const canonicalRelative = path.relative(canonicalRoot, canonicalTarget);
  if (!isContained(canonicalRelative) || canonicalRelative === '') {
    throw new Error('Target is outside the project root');
  }

  if (
    policy.exactRelativePath !== undefined &&
    canonicalRelative !== path.normalize(policy.exactRelativePath)
  ) {
    throw new Error('Target does not match the allowed target path');
  }
  if (
    policy.relativeDirectory !== undefined &&
    path.dirname(canonicalRelative) !== path.normalize(policy.relativeDirectory)
  ) {
    throw new Error('Target is outside the allowed directory');
  }
  if (
    policy.extension !== undefined &&
    path.extname(canonicalRelative) !== policy.extension
  ) {
    throw new Error(`Target must use the ${policy.extension} extension`);
  }

  const parts = canonicalRelative.split(path.sep);
  let current = canonicalRoot;
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    const stat = await optionalLstat(current);
    if (!stat) {
      break;
    }
    if (stat.isSymbolicLink()) {
      throw new Error('Target path must not contain symlinks');
    }
    if (index < parts.length - 1 && !stat.isDirectory()) {
      throw new Error('Target parent must be a directory');
    }
    if (index === parts.length - 1 && stat.isDirectory()) {
      throw new Error('Target must be a file');
    }

    const existingRealPath = await realpath(current);
    if (!isContained(path.relative(canonicalRoot, existingRealPath))) {
      throw new Error('Target real path is outside the project root');
    }
  }

  return canonicalTarget;
}
