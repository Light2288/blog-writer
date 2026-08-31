# Add Parenthetical Style Convention

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | Add Parenthetical Style Convention                     |
| **Type**      | chore                                                  |
| **Scope**     | Blog-writing conventions                                |
| **Created**   | 2026-08-31 00:00:00                                    |
| **Status**    | IMPLEMENTED                                            |

## Problem Statement

The blog-writing conventions do not currently capture the desired use of parentheses as a stylistic device. Without an explicit rule, English and Italian drafts may omit useful brief qualifications, ironic asides, or self-deprecating afterthoughts, resulting in prose that does not consistently reflect the requested voice.

## Desired Outcome

The conventions file should include a clear instruction to use parentheses naturally and fairly often in both English and Italian prose, especially for brief ironic comments, qualifications, and self-deprecating afterthoughts. The rule should encourage moderation: parentheses should not be stacked or used to bury the main point. The convention applies primarily to article bodies, with titles using parentheses only in rare, clearly appropriate cases.

## Acceptance Criteria

- [ ] The conventions file contains an explicit parenthetical-style rule covering both English and Italian.
- [ ] The rule recommends natural and fairly frequent use of parentheses for brief ironic comments, qualifications, and self-deprecating afterthoughts.
- [ ] The rule warns against stacking parentheses and against burying the main point inside them.
- [ ] The rule states that article bodies are the primary scope, while parentheses in titles should be rare and purposeful.
- [ ] The added guidance is consistent with the existing conventions' tone, structure, and formatting.

## Edge Cases & Error Handling

- **A sentence would become unclear with an aside:** Keep the main point outside the parentheses and rewrite or omit the aside.
- **Multiple parenthetical asides would appear together:** Avoid stacking them; use plain prose or restructure the passage.
- **A title seems to benefit from parentheses:** Use them only when they add clear value and do not make the title cumbersome.
- **English and Italian phrasing require different punctuation or placement:** Preserve grammatical correctness and natural usage in each language while following the same stylistic intent.

## Dependencies & Constraints

The change is limited to the project's conventions file and must preserve all existing guidance. It must not require changes to the article-writing workflow, MDX format, blog components, or source projects.

## Out of Scope

- Rewriting existing blog drafts or published articles.
- Changing other punctuation or voice conventions.
- Requiring parentheses in every paragraph, sentence, or title.
- Adding automated linting or validation for parenthetical usage.

## Notes

The requested wording is: “Use parentheses naturally and fairly often in both English and Italian, especially for brief ironic comments, qualifications, and self-deprecating afterthoughts. Avoid stacking them or burying the main point.” The implementation should adapt this wording to the conventions file rather than treating it as a mechanical quota.
