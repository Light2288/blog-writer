import path from 'node:path';

import { z } from 'zod/v4';

import { collectActivity } from '../activity.mjs';
import { scanRollouts } from '../history.mjs';

const boundsShape = {
  lo: z.number().int().nonnegative(),
  hi: z.number().int().nonnegative(),
};

function validBounds({ lo, hi }) {
  return (
    Number.isSafeInteger(lo) &&
    Number.isSafeInteger(hi) &&
    lo >= 0 &&
    lo < hi
  );
}

function success(value) {
  return {
    content: [{ type: 'text', text: JSON.stringify(value) }],
    structuredContent: value,
  };
}

function failure(message) {
  return {
    content: [{ type: 'text', text: message }],
    isError: true,
  };
}

export function createTopicHandlers(options = {}) {
  const collectActivityImpl = options.collectActivityImpl ?? collectActivity;
  const scanRolloutsImpl = options.scanRolloutsImpl ?? scanRollouts;
  const codexHome = options.codexHome;

  return {
    discover_projects: {
      config: {
        description: 'Discover project directories from bounded Codex history.',
        inputSchema: z.object(boundsShape),
        annotations: { readOnlyHint: true },
      },
      handler: async (args) => {
        if (!validBounds(args)) {
          return failure('Invalid discover_projects arguments');
        }
        try {
          const result = await scanRolloutsImpl({
            codexHome,
            lo: args.lo,
            hi: args.hi,
          });
          return success({
            projects: [
              ...new Set(result.sessions.map(({ project_dir }) => project_dir)),
            ].sort(),
            warnings: result.warnings,
            stats: result.stats,
          });
        } catch {
          return failure('Unable to discover projects from Codex history');
        }
      },
    },
    collect_activity: {
      config: {
        description:
          'Collect bounded Codex and Git activity for confirmed projects.',
        inputSchema: z.object({
          ...boundsShape,
          confirmed_projects: z.array(z.string()),
        }),
        annotations: { readOnlyHint: true },
      },
      handler: async (args) => {
        if (
          !validBounds(args) ||
          !Array.isArray(args.confirmed_projects) ||
          args.confirmed_projects.some(
            (project) => typeof project !== 'string' || !path.isAbsolute(project)
          )
        ) {
          return failure('Invalid collect_activity arguments');
        }
        try {
          return success(
            await collectActivityImpl({
              codexHome,
              lo: args.lo,
              hi: args.hi,
              confirmedProjects: [...new Set(args.confirmed_projects)],
            })
          );
        } catch {
          return failure('Unable to collect activity from local history');
        }
      },
    },
  };
}
