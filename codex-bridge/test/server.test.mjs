import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import {
  mkdtemp,
  mkdir,
  readFile,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

import { createServer, registerProfileTools } from '../src/server.mjs';

const run = promisify(execFile);

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
  desktop: ['discover_projects', 'collect_activity', 'write_topic_draft',
    'finalize_topics', 'write_conventions', 'read_source_file',
    'write_article_draft', 'finalize_article', 'publish_article'],
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
test('cli_writes_workflow_artifacts_to_the_primary_checkout_from_a_linked_worktree', async () => {
  const serverPath = fileURLToPath(
    new URL('../src/server.mjs', import.meta.url),
  );
  const scratch = await mkdtemp(join(tmpdir(), 'bridge-workflow-root-'));
  const primary = join(scratch, 'primary');
  const worktree = join(scratch, 'worktree');

  try {
    await run('git', ['init', '--quiet', primary]);
    await run('git', ['-C', primary, 'config', 'user.name', 'Synthetic Tester']);
    await run('git', [
      '-C',
      primary,
      'config',
      'user.email',
      'synthetic@example.invalid',
    ]);
    await writeFile(join(primary, 'README.md'), 'fixture\n');
    await run('git', ['-C', primary, 'add', 'README.md']);
    await run('git', ['-C', primary, 'commit', '--quiet', '-m', 'fixture']);
    await run('git', [
      '-C',
      primary,
      'worktree',
      'add',
      '--quiet',
      '-b',
      'fixture-worktree',
      worktree,
    ]);

    const transport = new StdioClientTransport({
      command: process.execPath,
      args: [serverPath, '--profile', 'conventions'],
      cwd: worktree,
      stderr: 'pipe',
    });
    const client = new Client({ name: 'workflow-root-test', version: '1.0.0' });

    try {
      await client.connect(transport);
      const result = await client.callTool({
        name: 'write_conventions',
        arguments: {
          content: '# Primary conventions\n',
          overwrite: false,
        },
      });

      assert.deepEqual(result.structuredContent, {
        path: join(await realpath(primary), 'CONVENTIONS.md'),
      });
      assert.equal(
        await readFile(join(primary, 'CONVENTIONS.md'), 'utf8'),
        '# Primary conventions\n',
      );
      await assert.rejects(readFile(join(worktree, 'CONVENTIONS.md')), {
        code: 'ENOENT',
      });
    } finally {
      await client.close();
    }
  } finally {
    await rm(scratch, { force: true, recursive: true });
  }
});

test('desktop_reuses_narrow_schemas_and_bounded_workflow_operations', async () => {
  const scratch = await mkdtemp(join(tmpdir(), 'desktop-sdk-'));
  const root = join(scratch, 'project');
  const serverPath = fileURLToPath(new URL('../src/server.mjs', import.meta.url));
  const clients = [];
  try {
    await run('git', ['init', '--quiet', root]);
    await Promise.all(['inputs', 'drafts', 'published'].map(dir => mkdir(join(root, dir))));
    const connect = async (profile) => {
      const client = new Client({ name: 'desktop-sdk-test', version: '1' });
      clients.push(client);
      await client.connect(new StdioClientTransport({
        command: process.execPath, args: [serverPath, '--profile', profile],
        cwd: root, stderr: 'pipe',
      }));
      return client;
    };
    const desktop = await connect('desktop');
    const catalog = (await desktop.listTools()).tools;
    assert.deepEqual(catalog.map(t => t.name), EXPECTED_PROFILE_TOOL_NAMES.desktop);
    for (const profile of ['topic', 'conventions', 'writer']) {
      const narrow = await connect(profile);
      for (const tool of (await narrow.listTools()).tools) {
        assert.deepEqual(catalog.find(t => t.name === tool.name), tool);
      }
    }
    const call = async (name, args) => {
      const result = await desktop.callTool({ name, arguments: args });
      assert.notEqual(result.isError, true, JSON.stringify(result));
      return result;
    };
    await call('write_topic_draft', {date:'2099-01-01', content:'# Topics\n\n| Status | DRAFT |\n', overwrite:false});
    await call('finalize_topics', {date:'2099-01-01'});
    assert.match(await readFile(join(root, 'inputs/topics-2099-01-01.md'), 'utf8'), /\| Status \| FINAL \|/);
    await call('write_conventions', {content:'# Conventions\n\nUse clear prose.\n', overwrite:false});
    const source = await call('read_source_file', {path:join(root,'CONVENTIONS.md'), confirmed_projects:[root]});
    assert.match(JSON.stringify(source), /Use clear prose/);
    const denied = await desktop.callTool({name:'read_source_file', arguments:{path:serverPath, confirmed_projects:[root]}});
    assert.equal(denied.isError, true);
    const draft = '---\ntitle:\n  en: Fixture\n  it: Prova\nsummary:\n  en: >\n    Fixture summary.\n  it: >\n    Riassunto di prova.\ndate: 2099-01-01\nlastmod: 2099-01-01\ntopic_key: desktop-fixture\ntags:\n  - id: engineering\n    label:\n      en: Engineering\n      it: Ingegneria\ndraft: true\nimages: []\n---\n\n<Lang value="en">\n\nEvidence.\n\n</Lang>\n\n<Lang value="it">\n\nProva.\n\n</Lang>\n';
    await call('write_article_draft', {slug:'desktop-fixture', content:draft, overwrite:false});
    await call('finalize_article', {slug:'desktop-fixture'});
    await assert.rejects(readFile(join(root,'inputs/published-topics.md')), {code:'ENOENT'});
    await assert.rejects(readFile(join(root,'published/desktop-fixture.mdx')), {code:'ENOENT'});
    await call('publish_article', {slug:'desktop-fixture', publication_date:'2099-01-02'});
    assert.match(await readFile(join(root,'published/desktop-fixture.mdx'),'utf8'), /draft: false/);
    await assert.rejects(readFile(join(root,'drafts/desktop-fixture.mdx')), {code:'ENOENT'});
    assert.equal(await readFile(join(root,'inputs/published-topics.md'),'utf8'), '# Published topics\n\n- desktop-fixture | desktop-fixture | published 2099-01-02\n');
  } finally {
    await Promise.all(clients.map(c => c.close()));
    await rm(scratch, {recursive:true, force:true});
  }
});
