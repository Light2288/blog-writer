import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { PassThrough } from 'node:stream';
import test from 'node:test';

import { createServer } from '../src/server.mjs';

const require = createRequire(import.meta.url);
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require(
  '@modelcontextprotocol/sdk/server/stdio.js'
);
const sdkPackage = require(
  '../node_modules/@modelcontextprotocol/sdk/package.json'
);

test('realSdkBoundary_constructs_server_and_connects_stdio_transport', async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const handlers = {
    write_conventions: {
      config: { description: 'Test-only conventions handler' },
      handler: async () => ({ content: [] }),
    },
  };

  const server = createServer({
    profile: 'conventions',
    projectRoot: '/test/blog-writer',
    dependencies: { handlers },
  });
  const transport = new StdioServerTransport(input, output);

  assert.equal(sdkPackage.version, '1.30.1');
  assert.equal(server instanceof McpServer, true);

  await server.connect(transport);
  assert.equal(input.listenerCount('data'), 1);

  await server.close();
  assert.equal(input.listenerCount('data'), 0);

  input.destroy();
  output.destroy();
});
