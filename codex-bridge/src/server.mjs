import { execFile } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { realpath } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { PROFILE_TOOL_NAMES, parseProfile } from './profiles.mjs';
import { createConventionsHandlers } from './tools/conventions.mjs';
import { createTopicHandlers } from './tools/topic.mjs';
import { createWriterHandlers } from './tools/writer.mjs';

const require = createRequire(import.meta.url);
const run = promisify(execFile);

function loadSdk() {
  const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
  const { StdioServerTransport } = require(
    '@modelcontextprotocol/sdk/server/stdio.js'
  );

  return { McpServer, StdioServerTransport };
}

export function registerProfileTools(server, profile, handlers) {
  const toolNames = PROFILE_TOOL_NAMES[profile];
  if (!toolNames) {
    throw new Error(`Unknown bridge profile: ${profile}`);
  }

  for (const name of toolNames) {
    const registration = handlers[name];
    if (!registration) {
      throw new Error(`Missing handler for profile tool: ${name}`);
    }

    server.registerTool(name, registration.config, registration.handler);
  }
}

function createProfileHandlers(profile, projectRoot) {
  switch (profile) {
    case 'topic':
      return createTopicHandlers({ projectRoot });
    case 'conventions':
      return createConventionsHandlers({ projectRoot });
    case 'writer':
      return createWriterHandlers({ projectRoot });
    default:
      throw new Error(`Unknown bridge profile: ${profile}`);
  }
}

export function createServer({ profile, projectRoot, dependencies }) {
  const resolvedDependencies = dependencies ?? {};
  const McpServerClass =
    resolvedDependencies.McpServerClass ?? loadSdk().McpServer;
  const handlers =
    resolvedDependencies.handlers ?? createProfileHandlers(profile, projectRoot);
  const server = new McpServerClass({
    name: 'blog-writer-codex-bridge',
    version: '1.0.0',
  });

  registerProfileTools(server, profile, handlers);
  void projectRoot;

  return server;
}

export async function resolveWorkflowRoot(projectRoot) {
  const { stdout } = await run('git', [
    '-C',
    projectRoot,
    'rev-parse',
    '--path-format=absolute',
    '--git-common-dir',
  ]);
  const commonDirectory = await realpath(stdout.trim());
  if (path.basename(commonDirectory) !== '.git') {
    throw new Error('Blog-Writer requires a standard Git working tree');
  }
  return realpath(path.dirname(commonDirectory));
}

async function startCli() {
  const profile = parseProfile(process.argv.slice(2));
  const dependencies = {};
  const server = createServer({
    profile,
    projectRoot: await resolveWorkflowRoot(process.cwd()),
    dependencies,
  });
  const transport = new (loadSdk().StdioServerTransport)();

  await server.connect(transport);
}

const entrypoint = process.argv[1];
if (
  entrypoint &&
  realpathSync(fileURLToPath(import.meta.url)) === realpathSync(entrypoint)
) {
  startCli().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
