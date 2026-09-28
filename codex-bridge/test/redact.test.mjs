import assert from 'node:assert/strict';
import test from 'node:test';

import { redactText } from '../src/redact.mjs';

test('redactText_replaces_secret_like_values_with_compatible_labels', () => {
  const input = [
    'client_secret: hunter2',
    'Authorization bearer abc.def.ghi',
    'api-key = key-value',
    'token: token-value',
    '0123456789abcdef0123456789abcdef',
    'GHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijk',
  ].join('\n');

  const result = redactText(input);

  assert.equal(
    result.text,
    [
      'client_secret=[REDACTED:client_secret]',
      'Authorization [REDACTED:bearer]',
      'api-key=[REDACTED:api_key]',
      'token=[REDACTED:token]',
      '[REDACTED:hex-secret]',
      '[REDACTED:base64-secret]',
    ].join('\n')
  );
  assert.equal(result.flagged, true);
  assert.deepEqual(result.reasons, [
    'client_secret',
    'api_key',
    'token',
    'bearer',
    'hex-secret',
    'base64-secret',
  ]);
});

test('redactText_reports_each_reason_only_once', () => {
  const result = redactText('token=first token=second Bearer one Bearer two');

  assert.equal(
    result.text,
    'token=[REDACTED:token] token=[REDACTED:token] [REDACTED:bearer] [REDACTED:bearer]'
  );
  assert.deepEqual(result.reasons, ['token', 'bearer']);
});

test('redactText_leaves_clean_prose_unflagged', () => {
  const input = 'Refined the rollout adapter and documented the design tradeoffs.';

  assert.deepEqual(redactText(input), {
    text: input,
    flagged: false,
    reasons: [],
  });
});
