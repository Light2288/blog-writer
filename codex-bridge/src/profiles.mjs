const PROFILE_ERROR =
  'Expected exactly one --profile value: topic, conventions, writer, desktop';

/** @type {Readonly<Record<'topic' | 'conventions' | 'writer' | 'desktop', readonly string[]>>} */
export const PROFILE_TOOL_NAMES = Object.freeze({
  topic: Object.freeze([
    'discover_projects',
    'collect_activity',
    'write_topic_draft',
    'finalize_topics',
  ]),
  conventions: Object.freeze(['write_conventions']),
  writer: Object.freeze([
    'read_source_file',
    'write_article_draft',
    'finalize_article',
    'publish_article',
  ]),
  desktop: Object.freeze([
    'discover_projects',
    'collect_activity',
    'write_topic_draft',
    'finalize_topics',
    'write_conventions',
    'read_source_file',
    'write_article_draft',
    'finalize_article',
    'publish_article',
  ]),
});

export function parseProfile(argv) {
  const profileFlags = argv
    .map((value, index) => ({ value, index }))
    .filter(({ value }) => value === '--profile');

  if (profileFlags.length !== 1) {
    throw new Error(PROFILE_ERROR);
  }

  const profile = argv[profileFlags[0].index + 1];
  if (!Object.hasOwn(PROFILE_TOOL_NAMES, profile)) {
    throw new Error(PROFILE_ERROR);
  }

  return profile;
}
