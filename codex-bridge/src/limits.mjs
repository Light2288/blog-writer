export const LIMITS = Object.freeze({
  rolloutFiles: 2_000,
  rolloutFileBytes: 16 * 1_048_576,
  rolloutLineBytes: 1_048_576,
  rolloutRecordsPerFile: 10_000,
  sessions: 100,
  textPartsPerSession: 40,
  charactersPerSession: 6_000,
  transcriptCharacters: 120_000,
  sourceFileCharacters: 20_000,
  sourceFileBytes: 1_048_576,
  generatedFileBytes: 1_048_576,
});
