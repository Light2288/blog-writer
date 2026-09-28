import { z } from 'zod/v4';

import { createConventionOperations } from '../conventions.mjs';

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

export function createConventionsHandlers(options = {}) {
  let conventionOperations = options.conventionOperations;
  function operations() {
    conventionOperations ??= createConventionOperations({
      projectRoot: options.projectRoot,
      atomicWriteImpl: options.atomicWriteImpl,
    });
    return conventionOperations;
  }

  return {
    write_conventions: {
      config: {
        description: 'Write only the project-root CONVENTIONS.md file.',
        inputSchema: z.object({
          content: z.string(),
          overwrite: z.boolean(),
        }),
      },
      handler: async (args) => {
        try {
          return success(await operations().writeConventions(args));
        } catch {
          return failure('Unable to write project conventions');
        }
      },
    },
  };
}
