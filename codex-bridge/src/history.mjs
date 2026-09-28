import { createReadStream } from 'node:fs';
import { opendir, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';

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

function addTerminalWarning(warnings, warning) {
  if (warnings.length < MAX_WARNINGS) {
    warnings.push(warning);
  } else {
    warnings[MAX_WARNINGS - 1] = warning;
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
      redactionReasons: new Set(),
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
    if (
      session.title === null &&
      typeof record.payload.title === 'string' &&
      record.payload.title
    ) {
      const redacted = redactText(record.payload.title);
      session.title = redacted.text.slice(0, LIMITS.charactersPerSession);
      for (const reason of redacted.reasons) {
        session.redactionReasons.add(reason);
      }
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
          const redacted = redactText(content.text);
          for (const reason of redacted.reasons) {
            session.redactionReasons.add(reason);
          }
          session.parts.push({
            role: payload.role,
            text: redacted.text.slice(0, LIMITS.charactersPerSession + 1),
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
  const input = createReadStream(file, {
    end: LIMITS.rolloutFileBytes - 1,
    highWaterMark: 64 * 1024,
  });
  let supported = false;
  let lineNumber = 0;
  let recordCount = 0;
  let fragments = [];
  let fragmentBytes = 0;
  let lineOversized = false;
  context.currentSessionId = null;

  function applyLine(lineBytes) {
    lineNumber += 1;
    context.lineNumber = lineNumber;
    if (lineOversized) {
      addWarning(context.warnings, {
        code: 'rollout_line_too_large',
        message: 'Skipped a Codex rollout line above the byte limit',
        file: path.basename(file),
        line: lineNumber,
      });
      return true;
    }

    const line = lineBytes.toString('utf8').replace(/\r$/u, '');
    if (!line.trim()) return true;
    recordCount += 1;
    if (recordCount > LIMITS.rolloutRecordsPerFile) {
      addTerminalWarning(context.warnings, {
        code: 'rollout_record_limit',
        message: 'Stopped reading a Codex rollout file at the record limit',
        file: path.basename(file),
        line: lineNumber,
      });
      return false;
    }

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
      return true;
    }
    if (applyRecord(record, context)) {
      supported = true;
      context.stats.supportedRecords += 1;
    }
    return true;
  }

  function appendFragment(fragment) {
    if (lineOversized) return;
    if (fragmentBytes + fragment.length > LIMITS.rolloutLineBytes) {
      fragments = [];
      fragmentBytes = 0;
      lineOversized = true;
      return;
    }
    fragments.push(fragment);
    fragmentBytes += fragment.length;
  }

  function finishLine() {
    const lineBytes = lineOversized
      ? Buffer.alloc(0)
      : Buffer.concat(fragments, fragmentBytes);
    const keepReading = applyLine(lineBytes);
    fragments = [];
    fragmentBytes = 0;
    lineOversized = false;
    return keepReading;
  }

  try {
    let keepReading = true;
    for await (const chunk of input) {
      let start = 0;
      while (keepReading) {
        const newline = chunk.indexOf(0x0a, start);
        if (newline === -1) {
          appendFragment(chunk.subarray(start));
          break;
        }
        appendFragment(chunk.subarray(start, newline));
        keepReading = finishLine();
        start = newline + 1;
        if (start >= chunk.length) break;
      }
      if (!keepReading) break;
    }
    if (keepReading && (fragmentBytes > 0 || lineOversized)) {
      finishLine();
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
  const reasons = [...session.redactionReasons];
  let text = '';
  let includedParts = 0;
  let truncated = session.totalParts > LIMITS.textPartsPerSession;

  for (const part of session.parts) {
    const separator = text ? '\n' : '';
    const rendered = `${part.role}: ${part.text}`;
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
    title: session.title ?? 'Codex session',
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
  const prunedFiles = [];
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
    if (fileStat.mtimeMs <= lo) {
      prunedFiles.push({ file, fileSize: fileStat.size });
      continue;
    }
    stats.scannedFiles += 1;
    if (fileStat.size > LIMITS.rolloutFileBytes) {
      addWarning(warnings, {
        code: 'rollout_file_too_large',
        message: 'Skipped a Codex rollout file above the byte limit',
        file: path.basename(file),
      });
      continue;
    }
    if (await parseRollout(file, context)) stats.supportedFiles += 1;
  }

  if (stats.supportedRecords === 0) {
    for (const { file, fileSize } of prunedFiles) {
      stats.scannedFiles += 1;
      if (fileSize > LIMITS.rolloutFileBytes) {
        addWarning(warnings, {
          code: 'rollout_file_too_large',
          message: 'Skipped a Codex rollout file above the byte limit',
          file: path.basename(file),
        });
        continue;
      }
      if (await parseRollout(file, context)) {
        stats.supportedFiles += 1;
        break;
      }
    }
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
