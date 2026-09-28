import assert from 'node:assert/strict';
import test from 'node:test';

import { PROFILE_TOOL_NAMES, parseProfile } from '../src/profiles.mjs';

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

test('parseProfile_accepts_exact_profiles', () => {
  assert.equal(parseProfile(['--profile', 'topic']), 'topic');
  assert.equal(parseProfile(['--profile', 'conventions']), 'conventions');
  assert.equal(parseProfile(['--profile', 'writer']), 'writer');
});

test('parseProfile_rejects_missing_or_unknown_profile', () => {
  const expectedMessage =
    'Expected exactly one --profile value: topic, conventions, writer';

  assert.throws(() => parseProfile([]), { message: expectedMessage });
  assert.throws(() => parseProfile(['--profile', 'admin']), {
    message: expectedMessage,
  });
  assert.throws(
    () => parseProfile(['--profile', 'topic', '--profile', 'writer']),
    { message: expectedMessage },
  );
});

test('profileToolNames_do_not_leak_cross_role_operations', () => {
  assert.deepEqual(PROFILE_TOOL_NAMES, EXPECTED_PROFILE_TOOL_NAMES);
  assert.equal(PROFILE_TOOL_NAMES.topic.includes('read_source_file'), false);
  assert.equal(
    PROFILE_TOOL_NAMES.conventions.includes('read_source_file'),
    false,
  );
  assert.equal(PROFILE_TOOL_NAMES.writer.includes('read_source_file'), true);
  assert.equal(Object.isFrozen(PROFILE_TOOL_NAMES), true);
  assert.equal(
    Object.values(PROFILE_TOOL_NAMES).every((toolNames) =>
      Object.isFrozen(toolNames),
    ),
    true,
  );
});
