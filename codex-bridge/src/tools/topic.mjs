import path from 'node:path';

import { z } from 'zod/v4';

import { collectActivity } from '../activity.mjs';
import { scanRollouts } from '../history.mjs';
import { createTopicOperations } from '../topics.mjs';
import { toolFailure } from './failures.mjs';

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

export function createTopicHandlers(options = {}) {
  const collectActivityImpl = options.collectActivityImpl ?? collectActivity;
  const scanRolloutsImpl = options.scanRolloutsImpl ?? scanRollouts;
  const codexHome = options.codexHome;
  let topicOperations = options.topicOperations;
  function operations() {
    topicOperations ??= createTopicOperations({
      projectRoot: options.projectRoot,
      atomicWriteImpl: options.atomicWriteImpl,
    });
    return topicOperations;
  }

  return {
    discover_projects: {
      config: {
        description: 'Discover project directories from bounded Codex history.',
        inputSchema: z.object(boundsShape),
        annotations: { readOnlyHint: true },
      },
      handler: async (args) => {
        if (!validBounds(args)) {
          return toolFailure(undefined, {
            code: 'invalid_arguments',
            operation: 'discover_projects',
          });
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
        } catch (error) {
          return toolFailure(error, {
            code: 'discover_projects_failed',
            operation: 'discover_projects',
          });
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
          return toolFailure(undefined, {
            code: 'invalid_arguments',
            operation: 'collect_activity',
          });
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
        } catch (error) {
          return toolFailure(error, {
            code: 'collect_activity_failed',
            operation: 'collect_activity',
          });
        }
      },
    },
    write_topic_draft: {
      config: {
        description: 'Write a validated date-stamped topic draft.',
        inputSchema: z.object({
          date: z.string(),
          content: z.string(),
          overwrite: z.boolean(),
        }),
      },
      handler: async (args) => {
        try {
          return success(await operations().writeTopicDraft(args));
        } catch (error) {
          return toolFailure(error, {
            code: 'topic_draft_write_failed',
            operation: 'write_topic_draft',
          });
        }
      },
    },
    finalize_topics: {
      config: {
        description: 'Finalize exactly one topic draft status marker.',
        inputSchema: z.object({ date: z.string() }),
      },
      handler: async (args) => {
        try {
          return success(await operations().finalizeTopics(args));
        } catch (error) {
          return toolFailure(error, {
            code: 'topic_finalize_failed',
            operation: 'finalize_topics',
          });
        }
      },
    },
  };
}
