const SAFE_CODES = new Set([
  'publication_failed_restored',
  'publication_rollback_incomplete',
]);

function safeSlug(slug) {
  return typeof slug === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(slug)
    ? slug
    : undefined;
}

export function toolFailure(error, { code, operation, slug }) {
  const payload = {
    code: SAFE_CODES.has(error?.code) ? error.code : code,
    operation,
  };
  const normalizedSlug = safeSlug(slug);
  if (normalizedSlug !== undefined) {
    payload.slug = normalizedSlug;
  }
  return {
    content: [{ type: 'text', text: JSON.stringify(payload) }],
    structuredContent: payload,
    isError: true,
  };
}
