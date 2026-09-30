import assert from 'node:assert/strict';
import { mkdtemp, rm, symlink } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

import { createServer, registerProfileTools } from '../src/server.mjs';

const EXPECTED_PROFILE_TOOL_NAMES = {
  topic: [
    'discover_projects',
    'collect_activity',
    'write_topic_draft',
    'finalize_topics',
  ],
  conventions: ['write_conventions'],
  writer: [
    'read_source_file',
    'write_article_draft',
    'finalize_article',
    'publish_article',
  ],
};

class FakeServer {
  constructor(serverInfo) {
    this.serverInfo = serverInfo;
    this.registrations = [];
  }

  registerTool(name, config, handler) {
    this.registrations.push({ name, config, handler });
  }
}

function createHandlers() {
  const handlers = {};

  for (const name of Object.values(EXPECTED_PROFILE_TOOL_NAMES).flat()) {
    handlers[name] = {
      config: { description: `Handler for ${name}` },
      handler: async () => ({ content: [] }),
    };
  }

  handlers.shell = {
    config: { description: 'Must never be exposed' },
    handler: async () => ({ content: [] }),
  };
  handlers.read_file = {
    config: { description: 'Must never be exposed' },
    handler: async () => ({ content: [] }),
  };

  return handlers;
}

test('registerProfileTools_registers_only_selected_names', () => {
  for (const [profile, expectedNames] of Object.entries(
    EXPECTED_PROFILE_TOOL_NAMES,
  )) {
    const server = new FakeServer({ name: 'test', version: '0' });
    const handlers = createHandlers();

    registerProfileTools(server, profile, handlers);

    assert.deepEqual(
      server.registrations.map(({ name }) => name),
      expectedNames,
    );
    for (const registration of server.registrations) {
      assert.equal(registration.config, handlers[registration.name].config);
      assert.equal(registration.handler, handlers[registration.name].handler);
    }
  }
});

test('createServer_does_not_register_arbitrary_shell_or_file_tools', () => {
  const handlers = createHandlers();

  for (const [profile, expectedNames] of Object.entries(
    EXPECTED_PROFILE_TOOL_NAMES,
  )) {
    const server = createServer({
      profile,
      projectRoot: '/test/blog-writer',
      dependencies: { handlers, McpServerClass: FakeServer },
    });
    const advertisedNames = server.registrations.map(({ name }) => name);

    assert.deepEqual(advertisedNames, expectedNames);
    assert.equal(advertisedNames.includes('shell'), false);
    assert.equal(advertisedNames.includes('read_file'), false);
  }
});

test('createServer_constructs_completed_real_handlers_without_injection', () => {
  for (const [profile, expectedNames] of Object.entries(
    EXPECTED_PROFILE_TOOL_NAMES,
  )) {
    const server = createServer({
      profile,
      projectRoot: '/test/blog-writer',
      dependencies: { McpServerClass: FakeServer },
    });

    assert.deepEqual(
      server.registrations.map(({ name }) => name),
      expectedNames,
    );
    for (const registration of server.registrations) {
      assert.equal(typeof registration.handler, 'function');
      assert.equal(typeof registration.config.description, 'string');
      assert.notEqual(registration.config.description.length, 0);
    }
  }
});

test('cli_starts_when_entrypoint_path_uses_a_symlink', async () => {
  const serverPath = fileURLToPath(
    new URL('../src/server.mjs', import.meta.url),
  );
  const scratch = await mkdtemp(join(tmpdir(), 'bridge-entrypoint-'));
  const linkedServerPath = join(scratch, 'server.mjs');
  await symlink(serverPath, linkedServerPath);

  try {
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: [linkedServerPath, '--profile', 'conventions'],
      cwd: dirname(dirname(serverPath)),
      stderr: 'pipe',
    });
    const client = new Client({ name: 'entrypoint-test', version: '1.0.0' });

    try {
      await client.connect(transport);
      const listed = await client.listTools();

      assert.deepEqual(
        listed.tools.map(({ name }) => name),
        ['write_conventions'],
      );
    } finally {
      await client.close();
    }
  } finally {
    await rm(scratch, { force: true, recursive: true });
  }
});
