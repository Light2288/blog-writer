import { execFile as nodeExecFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFile = promisify(nodeExecFile);
const MAX_WARNINGS = 100;

function warningFor(project) {
  return {
    code: 'git_collection_failed',
    message: 'Git collection failed; project was skipped',
    project_dir: project,
  };
}

function parseLog(stdout, project, lo, hi) {
  const records = [];
  for (const encoded of stdout.split('\u001e')) {
    const record = encoded.trim();
    if (!record) continue;
    const [sha, epochSeconds, ...subjectParts] = record.split('\u001f');
    const timestampMs = Number(epochSeconds) * 1_000;
    if (
      !/^[a-f0-9]{40}$/.test(sha) ||
      !Number.isFinite(timestampMs) ||
      timestampMs <= lo ||
      timestampMs > hi
    ) {
      continue;
    }
    const subject = subjectParts.join('\u001f');
    records.push({
      source: 'git',
      project_dir: project,
      timestamp: new Date(timestampMs).toISOString(),
      kind: 'commit',
      id: sha,
      title: subject,
      text: subject,
      metadata: {
        sha,
        short_sha: sha.slice(0, 7),
        subject,
      },
    });
  }
  return records;
}

export async function collectGitCommits({ projects, lo, hi }) {
  const records = [];
  const warnings = [];

  for (const project of projects) {
    try {
      const { stdout } = await execFile(
        'git',
        [
          '-C',
          project,
          'log',
          `--since=${new Date(lo).toISOString()}`,
          `--until=${new Date(hi).toISOString()}`,
          '--format=%H%x1f%ct%x1f%s%x1e',
        ],
        { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
      );
      records.push(...parseLog(stdout, project, lo, hi));
    } catch {
      if (warnings.length < MAX_WARNINGS) warnings.push(warningFor(project));
    }
  }

  records.sort(
    (left, right) =>
      left.timestamp.localeCompare(right.timestamp) ||
      left.id.localeCompare(right.id)
  );
  return { records, warnings };
}
