import { z } from 'zod/v4';

import { createArticleOperations } from '../articles.mjs';
import { readSourceFile } from '../source-files.mjs';

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

export function createWriterHandlers(options = {}) {
  const readSourceFileImpl = options.readSourceFileImpl ?? readSourceFile;
  let articleOperations = options.articleOperations;
  function operations() {
    articleOperations ??= createArticleOperations({
      projectRoot: options.projectRoot,
      atomicWriteImpl: options.atomicWriteImpl,
    });
    return articleOperations;
  }

  return {
    read_source_file: {
      config: {
        description: 'Read bounded UTF-8 text from confirmed project roots.',
        inputSchema: z.object({
          path: z.string(),
          confirmed_projects: z.array(z.string()),
        }),
        annotations: { readOnlyHint: true },
      },
      handler: async (args) => {
        try {
          return success(
            await readSourceFileImpl({
              path: args.path,
              confirmedProjects: args.confirmed_projects,
            }),
          );
        } catch {
          return failure('Unable to read the requested source file');
        }
      },
    },
    write_article_draft: {
      config: {
        description: 'Write a validated article draft under drafts/.',
        inputSchema: z.object({
          slug: z.string(),
          content: z.string(),
          overwrite: z.boolean(),
        }),
      },
      handler: async (args) => {
        try {
          return success(await operations().writeArticleDraft(args));
        } catch {
          return failure('Unable to write the article draft');
        }
      },
    },
    finalize_article: {
      config: {
        description: 'Finalize exactly one article draft marker.',
        inputSchema: z.object({ slug: z.string() }),
      },
      handler: async (args) => {
        try {
          return success(await operations().finalizeArticle(args));
        } catch {
          return failure('Unable to finalize the article draft');
        }
      },
    },
    publish_article: {
      config: {
        description: 'Publish one finalized article and update its ledger.',
        inputSchema: z.object({
          slug: z.string(),
          publication_date: z.string(),
        }),
      },
      handler: async ({ slug, publication_date: publicationDate }) => {
        try {
          return success(
            await operations().publishArticle({ slug, publicationDate }),
          );
        } catch {
          return failure('Unable to publish the article');
        }
      },
    },
  };
}
