import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, rm, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { scanRollouts } from '../src/history.mjs';
import { LIMITS } from '../src/limits.mjs';

const FIXTURES = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'fixtures',
  'rollouts'
);
const PROJECT_ALPHA = '/synthetic/project-alpha';
const PROJECT_BETA = '/synthetic/project-beta';
const LO = Date.parse('2026-09-28T09:00:00.000Z');
const HI = Date.parse('2026-09-28T14:00:00.000Z');

async function syntheticHome(t) {
  const root = await mkdtemp(path.join(tmpdir(), 'blog-writer-codex-home-'));
  const sessions = path.join(root, 'sessions');
  await mkdir(sessions, { recursive: true });
  t.after(() => rm(root, { recursive: true, force: true }));
  return { root, sessions };
}

async function copyFixture(home, name, destination = name) {
  const target = path.join(home.sessions, destination);
  await mkdir(path.dirname(target), { recursive: true });
  await cp(path.join(FIXTURES, name), target);
  await utimes(target, new Date(HI + 1_000), new Date(HI + 1_000));
  return target;
}

async function writeRollout(target, content) {
  await writeFile(target, content);
  await utimes(target, new Date(HI + 1_000), new Date(HI + 1_000));
}

function sessionLines({ id, cwd = PROJECT_ALPHA, timestamps, parts = [] }) {
  const lines = [
    JSON.stringify({
      timestamp: timestamps[0],
      type: 'session_meta',
      payload: { id, cwd, title: `Title ${id}` },
    }),
  ];
  parts.forEach((text, index) => {
    lines.push(
      JSON.stringify({
        timestamp: timestamps[index + 1] ?? timestamps.at(-1),
        type: 'response_item',
        payload: {
          id: `${id}-message-${index}`,
          type: 'message',
          role: index % 2 === 0 ? 'user' : 'assistant',
          content: [
            {
              type: index % 2 === 0 ? 'input_text' : 'output_text',
              text,
            },
          ],
        },
      })
    );
  });
  return `${lines.join('\n')}\n`;
}

test('scanRollouts_uses_CODEX_HOME_and_extracts_redacted_normalized_messages', async (t) => {
  const home = await syntheticHome(t);
  await copyFixture(home, 'supported.jsonl', 'nested/supported.jsonl');
  const previous = process.env.CODEX_HOME;
  process.env.CODEX_HOME = home.root;
  t.after(() => {
    if (previous === undefined) delete process.env.CODEX_HOME;
    else process.env.CODEX_HOME = previous;
  });

  const result = await scanRollouts({
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.equal(result.sessions.length, 1);
  assert.deepEqual(result.sessions[0], {
    source: 'codex',
    project_dir: PROJECT_ALPHA,
    timestamp: '2026-09-28T10:15:00.000Z',
    kind: 'session',
    id: 'session-supported',
    title: 'Codex ingestion work',
    text:
      'user: Implement the history adapter token=[REDACTED:token]\nassistant: Added bounded parsing.',
    metadata: {
      redacted: true,
      redaction_reasons: ['token'],
      text_parts: 2,
      truncated: false,
    },
  });
  assert.deepEqual(result.warnings, []);
});

test('scanRollouts_filters_on_latest_record_with_open_closed_boundaries', async (t) => {
  const home = await syntheticHome(t);
  const loIso = new Date(LO).toISOString();
  const hiIso = new Date(HI).toISOString();
  await writeRollout(
    path.join(home.sessions, 'at-lo.jsonl'),
    sessionLines({ id: 'at-lo', timestamps: [loIso], parts: [] })
  );
  await writeRollout(
    path.join(home.sessions, 'at-hi.jsonl'),
    sessionLines({ id: 'at-hi', timestamps: [hiIso], parts: [] })
  );
  await writeRollout(
    path.join(home.sessions, 'after-hi.jsonl'),
    sessionLines({
      id: 'after-hi',
      timestamps: ['2026-09-28T14:00:00.001Z'],
      parts: [],
    })
  );

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.deepEqual(result.sessions.map(({ id }) => id), ['at-hi']);
});

test('scanRollouts_returns_empty_when_supported_history_is_older_than_the_window', async (t) => {
  const home = await syntheticHome(t);
  const target = path.join(home.sessions, 'older-supported.jsonl');
  await writeFile(
    target,
    sessionLines({
      id: 'older-supported',
      timestamps: ['2026-09-28T08:00:00.000Z'],
      parts: ['older work'],
    })
  );
  await utimes(target, new Date(LO - 1_000), new Date(LO - 1_000));

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.deepEqual(result.sessions, []);
  assert.equal(result.stats.candidateFiles, 1);
  assert.equal(result.stats.supportedFiles, 1);
  assert.equal(result.stats.matchedSessions, 0);
});

test('scanRollouts_filters_working_directories_to_confirmed_projects', async (t) => {
  const home = await syntheticHome(t);
  await copyFixture(home, 'supported.jsonl');
  await writeRollout(
    path.join(home.sessions, 'beta.jsonl'),
    sessionLines({
      id: 'session-beta',
      cwd: PROJECT_BETA,
      timestamps: ['2026-09-28T10:30:00.000Z'],
      parts: ['beta work'],
    })
  );

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_BETA],
  });

  assert.deepEqual(result.sessions.map(({ project_dir }) => project_dir), [
    PROJECT_BETA,
  ]);
});

test('scanRollouts_deduplicates_stable_message_ids', async (t) => {
  const home = await syntheticHome(t);
  await copyFixture(home, 'duplicate.jsonl');

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.equal(
    result.sessions[0].text,
    'user: Only include me once.\nassistant: Included once.'
  );
  assert.equal(result.sessions[0].metadata.text_parts, 2);
});

test('scanRollouts_redacts_secret_like_session_titles', async (t) => {
  const home = await syntheticHome(t);
  const content = JSON.stringify({
    timestamp: '2026-09-28T11:00:00.000Z',
    type: 'session_meta',
    payload: {
      id: 'secret-title',
      cwd: PROJECT_ALPHA,
      title: 'Investigate token=title-secret',
    },
  });
  await writeRollout(path.join(home.sessions, 'secret-title.jsonl'), `${content}\n`);

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.equal(
    result.sessions[0].title,
    'Investigate token=[REDACTED:token]'
  );
  assert.equal(result.sessions[0].metadata.redacted, true);
  assert.deepEqual(result.sessions[0].metadata.redaction_reasons, ['token']);
});

test('scanRollouts_redacts_complete_strings_before_output_caps', async (t) => {
  const home = await syntheticHome(t);
  const prefix = `${'p '.repeat(2_985)} `;
  const secret = '0123456789abcdef0123456789abcdef';
  const sensitiveText = `${prefix}${secret} safe-tail`;
  const content = [
    JSON.stringify({
      timestamp: '2026-09-28T11:00:00.000Z',
      type: 'session_meta',
      payload: {
        id: 'boundary-secret',
        cwd: PROJECT_ALPHA,
        title: sensitiveText,
      },
    }),
    JSON.stringify({
      timestamp: '2026-09-28T11:01:00.000Z',
      type: 'response_item',
      payload: {
        id: 'boundary-secret-message',
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text: sensitiveText }],
      },
    }),
  ].join('\n');
  await writeRollout(
    path.join(home.sessions, 'boundary-secret.jsonl'),
    `${content}\n`
  );

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });
  const [session] = result.sessions;

  assert.match(session.title, /\[REDACTED:hex-secret\]/);
  assert.match(session.text, /\[REDACTED:hex-secret\]/);
  assert.doesNotMatch(session.title, /0123456789abcdef/);
  assert.doesNotMatch(session.text, /0123456789abcdef/);
  assert.equal(session.metadata.redacted, true);
  assert.deepEqual(session.metadata.redaction_reasons, ['hex-secret']);
});

test('scanRollouts_bounds_parts_and_characters_per_session', async (t) => {
  const home = await syntheticHome(t);
  const parts = Array.from(
    { length: LIMITS.textPartsPerSession + 1 },
    (_, index) => `${String(index).padStart(2, '0')}-part`
  );
  await writeRollout(
    path.join(home.sessions, 'long.jsonl'),
    sessionLines({
      id: 'long',
      timestamps: ['2026-09-28T10:00:00.000Z'],
      parts,
    })
  );
  await writeRollout(
    path.join(home.sessions, 'long-characters.jsonl'),
    sessionLines({
      id: 'long-characters',
      timestamps: ['2026-09-28T10:01:00.000Z'],
      parts: ['word '.repeat(LIMITS.charactersPerSession / 5 + 1)],
    })
  );

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });
  const partLimited = result.sessions.find(({ id }) => id === 'long');
  const characterLimited = result.sessions.find(
    ({ id }) => id === 'long-characters'
  );

  assert.equal(partLimited.metadata.text_parts, LIMITS.textPartsPerSession);
  assert.equal(partLimited.metadata.truncated, true);
  assert.equal(partLimited.text.includes('40-'), false);
  assert.equal(characterLimited.text.length, LIMITS.charactersPerSession);
  assert.equal(characterLimited.metadata.text_parts, 1);
  assert.equal(characterLimited.metadata.truncated, true);
});

test('scanRollouts_bounds_sessions_and_total_transcript_characters', async (t) => {
  const home = await syntheticHome(t);
  const writes = [];
  for (let index = 0; index < LIMITS.sessions + 1; index += 1) {
    writes.push(
      writeRollout(
        path.join(home.sessions, `${String(index).padStart(3, '0')}.jsonl`),
        sessionLines({
          id: `session-${String(index).padStart(3, '0')}`,
          timestamps: [
            new Date(LO + 1 + index).toISOString(),
            new Date(LO + 1 + index).toISOString(),
          ],
          parts: ['word '.repeat(LIMITS.charactersPerSession / 5)],
        })
      )
    );
  }
  await Promise.all(writes);

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });

  assert.equal(result.sessions.length, 20);
  assert.equal(
    result.sessions.reduce((total, session) => total + session.text.length, 0),
    LIMITS.transcriptCharacters
  );
  assert.equal(result.stats.sessionsTruncated, 1);
  assert.equal(result.stats.transcriptTruncated, true);
});

test('scanRollouts_warns_safely_for_malformed_lines_and_ignores_mixed_unknown_records', async (t) => {
  const home = await syntheticHome(t);
  await copyFixture(home, 'malformed.jsonl');
  await copyFixture(home, 'supported.jsonl');

  const result = await scanRollouts({
    codexHome: home.root,
    lo: LO,
    hi: HI,
    confirmedProjects: [PROJECT_ALPHA],
  });
  const warningText = JSON.stringify(result.warnings);

  assert.equal(result.sessions.length, 2);
  assert.equal(result.stats.malformedLines, 1);
  assert.match(warningText, /malformed JSON/i);
  assert.doesNotMatch(warningText, /THIS_RAW_SECRET|do-not-leak/);
});

test('scanRollouts_fails_closed_for_missing_or_zero_supported_history', async (t) => {
  const home = await syntheticHome(t);
  const unsupported = await copyFixture(home, 'unsupported.jsonl');
  await utimes(unsupported, new Date(LO - 1_000), new Date(LO - 1_000));

  await assert.rejects(
    scanRollouts({
      codexHome: home.root,
      lo: LO,
      hi: HI,
      confirmedProjects: [PROJECT_ALPHA],
    }),
    /no supported Codex rollout records.*future_message_v99.*future_session_v99/i
  );
  await assert.rejects(
    scanRollouts({
      codexHome: path.join(home.root, 'missing'),
      lo: LO,
      hi: HI,
      confirmedProjects: [PROJECT_ALPHA],
    }),
    /Codex history directory is unavailable/i
  );
});

test('scanRollouts_enforces_the_2000_candidate_file_cap', async (t) => {
  const home = await syntheticHome(t);
  const writes = [];
  for (let index = 0; index <= LIMITS.rolloutFiles; index += 1) {
    writes.push(
      writeFile(
        path.join(home.sessions, `${String(index).padStart(4, '0')}.jsonl`),
        '{}\n'
      )
    );
  }
  await Promise.all(writes);

  await assert.rejects(
    scanRollouts({
      codexHome: home.root,
      lo: LO,
      hi: HI,
      confirmedProjects: [PROJECT_ALPHA],
    }),
    /more than 2000 candidate rollout files/i
  );
});
