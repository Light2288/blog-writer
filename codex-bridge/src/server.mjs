import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

import { PROFILE_TOOL_NAMES, parseProfile } from './profiles.mjs';

const require = createRequire(import.meta.url);

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

export function createServer({ profile, projectRoot, dependencies }) {
  const resolvedDependencies = dependencies ?? {};
  const McpServerClass =
    resolvedDependencies.McpServerClass ?? loadSdk().McpServer;
  const handlers = resolvedDependencies.handlers ?? {};
  const server = new McpServerClass({
    name: 'blog-writer-codex-bridge',
    version: '1.0.0',
  });

  registerProfileTools(server, profile, handlers);
  void projectRoot;

  return server;
}

async function startCli() {
  const profile = parseProfile(process.argv.slice(2));
  const dependencies = {};
  const server = createServer({
    profile,
    projectRoot: process.cwd(),
    dependencies,
  });
  const transport = new (loadSdk().StdioServerTransport)();

  await server.connect(transport);
}

const entrypoint = process.argv[1];
if (entrypoint && fileURLToPath(import.meta.url) === entrypoint) {
  startCli().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
