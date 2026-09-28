import { createReadStream } from 'node:fs';
import { opendir, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import readline from 'node:readline';

import { LIMITS } from './limits.mjs';
import { redactText } from './redact.mjs';

const MAX_WARNINGS = 100;
const SUPPORTED_TEXT_TYPES = new Set(['input_text', 'output_text', 'text']);

function validTimestamp(value) {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function addWarning(warnings, warning) {
  if (warnings.length < MAX_WARNINGS) {
    warnings.push(warning);
  }
}

async function discoverJsonlFiles(directory, files) {
  let entries;
  try {
    entries = await opendir(directory);
  } catch (error) {
    if (error?.code === 'ENOENT' || error?.code === 'ENOTDIR') {
      throw new Error('Codex history directory is unavailable');
    }
    throw new Error('Unable to discover Codex rollout files');
  }

  for await (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await discoverJsonlFiles(entryPath, files);
    } else if (entry.isFile() && entry.name.endsWith('.jsonl')) {
      files.push(entryPath);
      if (files.length > LIMITS.rolloutFiles) {
        throw new Error(
          `Codex history contains more than ${LIMITS.rolloutFiles} candidate rollout files`
        );
      }
    }
  }
}

function sessionFor(sessions, id) {
  let session = sessions.get(id);
  if (!session) {
    session = {
      id,
      cwd: null,
      title: null,
      latestTimestamp: null,
      messageIds: new Set(),
      parts: [],
      totalParts: 0,
    };
    sessions.set(id, session);
  }
  return session;
}

function updateLatest(session, timestamp) {
  if (
    timestamp !== null &&
    (session.latestTimestamp === null || timestamp > session.latestTimestamp)
  ) {
    session.latestTimestamp = timestamp;
  }
}

function applyRecord(record, context) {
  const { sessions, unsupportedTypes } = context;
  const timestamp = validTimestamp(record?.timestamp);

  if (record?.type === 'session_meta') {
    const id = record.payload?.id;
    const cwd = record.payload?.cwd;
    if (typeof id !== 'string' || typeof cwd !== 'string') {
      return false;
    }
    const session = sessionFor(sessions, id);
    session.cwd ??= cwd;
    if (typeof record.payload.title === 'string' && record.payload.title) {
      session.title ??= record.payload.title;
    }
    updateLatest(session, timestamp);
    context.currentSessionId = id;
    return true;
  }

  if (record?.type === 'response_item') {
    const payload = record.payload;
    if (
      payload?.type !== 'message' ||
      !['user', 'assistant'].includes(payload.role) ||
      !Array.isArray(payload.content) ||
      context.currentSessionId === null
    ) {
      return false;
    }

    const session = sessionFor(sessions, context.currentSessionId);
    updateLatest(session, timestamp);
    const messageId =
      typeof payload.id === 'string'
        ? payload.id
        : `${context.fileIndex}:${context.lineNumber}`;
    if (session.messageIds.has(messageId)) {
      return true;
    }
    session.messageIds.add(messageId);

    for (const content of payload.content) {
      if (
        SUPPORTED_TEXT_TYPES.has(content?.type) &&
        typeof content.text === 'string'
      ) {
        session.totalParts += 1;
        if (session.parts.length < LIMITS.textPartsPerSession) {
          session.parts.push({
            role: payload.role,
            text: content.text.slice(0, LIMITS.charactersPerSession + 1),
          });
        }
      }
    }
    return true;
  }

  if (typeof record?.type === 'string') {
    unsupportedTypes.add(record.type);
  }
  if (context.currentSessionId !== null) {
    updateLatest(sessionFor(sessions, context.currentSessionId), timestamp);
  }
  return false;
}

async function parseRollout(file, context) {
  const input = createReadStream(file, { encoding: 'utf8' });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let supported = false;
  let lineNumber = 0;
  context.currentSessionId = null;

  try {
    for await (const line of lines) {
      lineNumber += 1;
      context.lineNumber = lineNumber;
      if (!line.trim()) continue;
      let record;
      try {
        record = JSON.parse(line);
      } catch {
        context.stats.malformedLines += 1;
        addWarning(context.warnings, {
          code: 'malformed_json',
          message: 'Skipped malformed JSON in a Codex rollout file',
          file: path.basename(file),
          line: lineNumber,
        });
        continue;
      }
      if (applyRecord(record, context)) {
        supported = true;
        context.stats.supportedRecords += 1;
      }
    }
  } catch {
    addWarning(context.warnings, {
      code: 'rollout_read_failed',
      message: 'Skipped an unreadable Codex rollout file',
      file: path.basename(file),
    });
  }
  return supported;
}

function normalizeSession(session) {
  const redactedTitle = redactText(
    (session.title ?? 'Codex session').slice(0, LIMITS.charactersPerSession)
  );
  const reasons = [...redactedTitle.reasons];
  let text = '';
  let includedParts = 0;
  let truncated = session.totalParts > LIMITS.textPartsPerSession;

  for (const part of session.parts) {
    const redacted = redactText(part.text);
    for (const reason of redacted.reasons) {
      if (!reasons.includes(reason)) reasons.push(reason);
    }
    const separator = text ? '\n' : '';
    const rendered = `${part.role}: ${redacted.text}`;
    const remaining = LIMITS.charactersPerSession - text.length;
    if (remaining <= 0) {
      truncated = true;
      break;
    }
    const addition = `${separator}${rendered}`;
    text += addition.slice(0, remaining);
    includedParts += 1;
    if (addition.length > remaining) {
      truncated = true;
      break;
    }
  }

  return {
    source: 'codex',
    project_dir: session.cwd,
    timestamp: new Date(session.latestTimestamp).toISOString(),
    kind: 'session',
    id: session.id,
    title: redactedTitle.text.slice(0, LIMITS.charactersPerSession),
    text,
    metadata: {
      redacted: reasons.length > 0,
      redaction_reasons: reasons,
      text_parts: includedParts,
      truncated,
    },
  };
}

export async function scanRollouts(options) {
  const { lo, hi, confirmedProjects } = options;
  const codexHome =
    options.codexHome ?? process.env.CODEX_HOME ?? path.join(homedir(), '.codex');
  const historyDirectory = path.join(codexHome, 'sessions');
  const files = [];
  await discoverJsonlFiles(historyDirectory, files);
  files.sort();

  const warnings = [];
  const sessions = new Map();
  const unsupportedTypes = new Set();
  const stats = {
    candidateFiles: files.length,
    scannedFiles: 0,
    supportedFiles: 0,
    supportedRecords: 0,
    malformedLines: 0,
    matchedSessions: 0,
    sessionsTruncated: 0,
    transcriptCharacters: 0,
    transcriptTruncated: false,
  };
  const context = {
    sessions,
    unsupportedTypes,
    warnings,
    stats,
    currentSessionId: null,
    fileIndex: 0,
    lineNumber: 0,
  };

  for (const [fileIndex, file] of files.entries()) {
    context.fileIndex = fileIndex;
    let fileStat;
    try {
      fileStat = await stat(file);
    } catch {
      addWarning(warnings, {
        code: 'rollout_stat_failed',
        message: 'Skipped an unavailable Codex rollout file',
        file: path.basename(file),
      });
      continue;
    }
    if (fileStat.mtimeMs <= lo) continue;
    stats.scannedFiles += 1;
    if (await parseRollout(file, context)) stats.supportedFiles += 1;
  }

  if (stats.supportedRecords === 0) {
    const types = [...unsupportedTypes].sort();
    const suffix = types.length ? `: ${types.join(', ')}` : '';
    throw new Error(`No supported Codex rollout records were found${suffix}`);
  }

  const allowedProjects =
    confirmedProjects === undefined ? null : new Set(confirmedProjects);
  const matching = [...sessions.values()]
    .filter(
      (session) =>
        session.latestTimestamp !== null &&
        session.latestTimestamp > lo &&
        session.latestTimestamp <= hi &&
        (allowedProjects === null || allowedProjects.has(session.cwd))
    )
    .sort(
      (left, right) =>
        right.latestTimestamp - left.latestTimestamp ||
        left.id.localeCompare(right.id)
    );
  stats.matchedSessions = matching.length;
  stats.sessionsTruncated = Math.max(0, matching.length - LIMITS.sessions);

  const normalized = [];
  for (const session of matching.slice(0, LIMITS.sessions)) {
    const record = normalizeSession(session);
    const remaining =
      LIMITS.transcriptCharacters - stats.transcriptCharacters;
    if (record.text.length > remaining) {
      if (remaining > 0) {
        record.text = record.text.slice(0, remaining);
        record.metadata.truncated = true;
        normalized.push(record);
        stats.transcriptCharacters += record.text.length;
      }
      stats.transcriptTruncated = true;
      break;
    }
    normalized.push(record);
    stats.transcriptCharacters += record.text.length;
  }
  if (normalized.length < Math.min(matching.length, LIMITS.sessions)) {
    stats.transcriptTruncated = true;
  }

  return { sessions: normalized, warnings, stats };
}
