const RULES = [
  {
    pattern: /\b(client_secret)\b\s*[:=]\s*(\S+)/gi,
    reason: 'client_secret',
    preserveKey: true,
  },
  {
    pattern: /\b(api[_-]?key)\b\s*[:=]\s*(\S+)/gi,
    reason: 'api_key',
    preserveKey: true,
  },
  {
    pattern: /\b(token)\b\s*[:=]\s*(\S+)/gi,
    reason: 'token',
    preserveKey: true,
  },
  { pattern: /\bbearer\s+(\S+)/gi, reason: 'bearer' },
  { pattern: /\b[A-Fa-f0-9]{32,}\b/g, reason: 'hex-secret' },
  {
    pattern: /\b[A-Za-z0-9+/]{32,}={0,2}\b/g,
    reason: 'base64-secret',
  },
];

export function redactText(input) {
  let text = String(input);
  const reasons = [];

  for (const rule of RULES) {
    let matched = false;
    text = text.replace(rule.pattern, (...match) => {
      matched = true;
      if (rule.preserveKey) {
        return `${match[1]}=[REDACTED:${rule.reason}]`;
      }
      return `[REDACTED:${rule.reason}]`;
    });
    if (matched) {
      reasons.push(rule.reason);
    }
  }

  return { text, flagged: reasons.length > 0, reasons };
}
