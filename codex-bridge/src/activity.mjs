import { collectGitCommits } from './git.mjs';
import { scanRollouts } from './history.mjs';

export async function collectActivity(options) {
  const history = await scanRollouts({
    codexHome: options.codexHome,
    lo: options.lo,
    hi: options.hi,
    confirmedProjects: options.confirmedProjects,
  });
  const git = await collectGitCommits({
    projects: options.confirmedProjects,
    lo: options.lo,
    hi: options.hi,
  });
  const records = [...history.sessions, ...git.records].sort(
    (left, right) =>
      left.timestamp.localeCompare(right.timestamp) ||
      left.source.localeCompare(right.source) ||
      left.id.localeCompare(right.id)
  );

  return {
    records,
    warnings: [...history.warnings, ...git.warnings],
    stats: {
      ...history.stats,
      codexRecords: history.sessions.length,
      gitRecords: git.records.length,
      totalRecords: records.length,
    },
  };
}
