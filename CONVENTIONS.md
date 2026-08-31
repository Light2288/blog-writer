# Writing Conventions

<!--
  This is CONVENTIONS.md — the file the `blog-writer` agent reads every run.
  It is authored via the `author-conventions` interview (seeded from
  CONVENTIONS.template.md). The pristine template is never edited in place.

  Placeholder convention: every unfilled field is a single canonical HTML
  comment of the form `<!-- TODO: ... -->`. A section counts as "unfilled" when
  its only content is one or more `<!-- TODO: ... -->` markers; the blog-writer
  treats a CONVENTIONS.md whose sections are all unfilled as "missing
  conventions" and refuses to draft.

  Keep the eight section headings below stable and in this order — the
  blog-writer references them by name.

  Note: this file is written in English (consistent with the specs, skills,
  agents, and tests). Article content itself stays bilingual (EN + IT) per the
  Bilingual Policy. Short tone examples may be kept in Italian as voice samples.
-->

## Voice & Tone

- **Persona**: write in the **first person** ("I"), mainly narrating what I
  actually did. Address the reader as **"you"** only **sparingly**: direct
  second-person asides are occasional and purposeful, not on every paragraph.
  This applies to **both languages**. When a "you" sentence feels forced or
  reads awkwardly, **recast it** (impersonal, first-person, or passive) rather
  than keep it; in Italian especially, prefer rephrasing over a literal "tu"
  (e.g. "il tono giudicalo tu" → "sul tono, giudizio sospeso"). The tone is
  never impersonal overall, but individual sentences need not address the reader.
- **Register**: casual and friendly, with an **ironic, playful** edge, yet
  always **professional**. The goal is to explain the technical details
  (normally fit for a technical audience too) while keeping the reader
  entertained: land jokes and asides that make reading fun without ever diluting
  the technical substance.
- **Humour**: welcome and encouraged (light irony, jokes), as long as it never
  buries the technical content and stays professional. Favour **self-deprecating,
  auto-ironic** notes about my own work over merely observational wit. For
  example: going through my own git commits is "like dumpster-diving"; a messy
  series of commits reads "fix", "fix again", "ok now really fix". The narrator
  is a little hapless, and that is part of the joke.
- **Parentheses**: use them naturally and fairly often in both English and
  Italian article bodies for brief ironic comments, qualifications, and
  self-deprecating afterthoughts. This is not a quota. Do not stack parenthetical
  asides or bury the main point inside them; rewrite or omit an aside when
  clarity suffers. Use parentheses in titles only rarely and purposefully (and
  never when they make the title cumbersome).
- **Rhythm**: **varied** (short, direct sentences for the key points; longer,
  more articulated ones when something needs depth).

## Article Structure

- **Skeleton**: mostly **narrative / chronological**, with no rigid template —
  tell the work as a story (context → problem → what I did → outcome). When the
  topic calls for it, the classic **intro → body → conclusion** is fine too.
  Choose based on the topic.
- **TOC**: **almost never**. Include a
  `<TOCInline toc={props.toc} exclude="..." />` only in exceptional cases (an
  unusually long, heavily sectioned article).
- **Length**: **variable** with the topic, but **never excessive** to the point
  of boring. Practical ceiling ~**10 minutes of reading** (roughly ~2000-2200
  words). Tune length to the best practices for this kind of blog and to the
  narrative-technical tone; concise beats verbose.
- **Headings**: **few**, mainly second level (`##`) to separate the main story
  beats. Avoid deep nesting.
- **Repository link**: when the article is about a specific project that has a
  **public GitHub repository**, reference the repo link somewhere in the piece
  (naturally, e.g. on first mention of the project, or in the closing). Only if
  it is **relevant and the repo actually exists / is public**. Never invent or
  guess a URL, and never link a private or work repository (see Taboos).

## Bilingual Policy

- **Flow**: **English-first** (English is the canonical language: write and
  iterate the English body first, then produce the Italian). English is the
  blog's publishing default; note, however, that the audience is likely mostly
  Italian, so the IT version must be equally high quality, not an afterthought.
- **EN ↔ IT relationship**: a **balanced mix** of faithful content translation,
  **tone adaptation**, and **free rewriting** where needed. Italian must read
  natively: irony, jokes, idioms, and references are **localized** for the
  Italian reader, not translated literally. Rephrasing sentences and examples is
  allowed, as long as technical content and structure stay equivalent to the
  English.
- **Technical terms**: common technical terms (e.g. deploy, commit, build,
  merge, bug, pull request...) **stay in English** even in the Italian text.
- **Code**: code, code comments, and strings are **never translated** (they stay
  identical in both versions).

### Italian translation: best practices

These rules come from real corrections and exist to kill the "mechanical
translation" feel. The Italian is a **rewrite**, not a translation.

- **Keep "half-technical" terms in English** when the Italian equivalent reads
  odd or unusual to a developer. Examples: `git history` (not "la storia di
  git"), "un errore di **type**" (not "di tipo"), **secrets** (not "segreti"),
  **guardrails** (not "protezioni"), **agent** (not "agente"/"mestiere"),
  **prompt**, **runtime**. When in doubt, favour the term a developer would
  actually say out loud in Italian.
- **Never translate metaphors literally.** If an English image does not land in
  Italian, **replace it** with a native one that carries the same idea (e.g. the
  "decorative gate in a field" became "una porta blindata montata su una parete
  di cartongesso"; "belt and braces" became "due sicure invece di una"). A
  metaphor that has to be explained is already dead.
- **Avoid rare/stilted words** that a fluent speaker would not use casually
  (avoid e.g. "bighellonare", "acquattarsi", "mestiere" for a software role).
  Prefer common, spoken-register vocabulary.
- **Don't calque English syntax.** Recast the sentence in natural Italian word
  order (e.g. "tutto il resto chiede prima" → "per tutto il resto, prima
  chiedi"; "quanto, di costruire un agent, sia..." → "quanta parte della
  costruzione di un agent sia...").
- **Recast "you" more aggressively than in English** (see Voice & Tone). A "you"
  that is fine and sparing in English often reads worse in Italian; when in
  doubt, drop the second person entirely (e.g. "il tono giudicalo tu" → "sul
  tono, giudizio sospeso").
- **Watch verb tense and agreement**: keep tenses consistent with the narration
  (a present-tense description stays present in Italian too).
- **Read it aloud test**: if a sentence would make a native speaker pause and
  re-read, rewrite it. Correctness is not enough; it has to *sound* right.

### Italian humour: register and references (IT only)

The Italian version can and should **lean harder into irony and the surreal**
than the English, drawing explicitly on **Paolo Villaggio (Fantozzi)** and
**Daniele Luttazzi**. These references are **for the Italian body only** (the
English keeps its own, lighter ironic voice).

- **Fantozzi register**: tragicomic hyperbole and bureaucratic-epic word choices
  applied to trivial tech mishaps. The adjective **"spettacolare"** used for a
  catastrophe is the canonical move (e.g. "un modo *spettacolare* di buttare via
  il lavoro"). Also: "mostruoso", the put-upon-employee fatalism, the dignified
  suffering of the narrator.
- **Luttazzi device**: a sentence that starts plausible and extends into a
  precise, over-specified, faintly absurd image (e.g. "la differenza tra leggere
  un contratto di persona e farselo raccontare al telefono da uno sconosciuto
  che ha imparato da poco la tua lingua mentre viaggia su un treno in un tratto
  con diverse gallerie"). Over-specification is the joke; keep it logical, not
  random.
- **Pop-culture references (80s/90s, for someone who grew up then)**: sprinkle
  **sparingly**, at most one or two per article, always in service of the point,
  never forced:
  - **Italian**: Fantozzi and its catchphrases and set-pieces; classic Italian
    TV moments; commedia/cinepanettoni and light comedies of the era ("Yuppies",
    films with De Sica, Boldi, Jerry Calà, Ezio Greggio, and similar).
  - **International (same era or earlier)**: e.g. *Animal House*, *The Blues
    Brothers*, *American Pie*, and comparable well-known comedies.
- **Guardrails on references**: they must stay **professional and inclusive** (a
  reader who misses the reference should still understand the sentence), respect
  the Taboos (no vulgarity, no offence), and never bury the technical substance.
  If a reference needs a footnote to work, cut it.

## MDX Conventions

**Allowed** component set (never invent components outside this list):

- `<Lang value="en">` / `<Lang value="it">` — blocks wrapping each language's
  body.
- `<TOCInline toc={props.toc} exclude="..." />` — table of contents (see Article
  Structure: almost never).
- Fenced code blocks using the `lang:filename` info-string convention.
- Footnotes (`[^1]` and their definitions) — **almost never** (see below).
- `<video>` with nested `<source>`.
- Images via markdown or the frontmatter `images` list.

Usage preferences:

- **Code fences**: **name the file** when the code comes from a real file (e.g.
  ```` ```ts:contentlayer.config.ts ````); for generic snippets or terminal
  commands use the **language only** (e.g. ```` ```bash ````).
- **Footnotes**: use with **extreme parsimony (almost never)** — Italian
  translation of footnote text currently **does not work**, so avoid them;
  prefer inline text or rephrasing.
- **Images**: only when they genuinely aid understanding.
- **Video**: only when **indispensable**.
- Overall goal: **clean text**, no component overload.

## Frontmatter Conventions

- **`summary`**: **short**, 1-2 sentences (~20-40 words), a hook that invites
  reading. Written as a `>` block scalar, in both languages (`en` and `it`),
  following the Bilingual Policy (IT adapted, not translated literally).
- **`date` / `lastmod`**: `date` = article creation date (never changes);
  `lastmod` = last-edit date, **updated on every subsequent edit**. On first
  draft they coincide.
- **`images`**: **empty list by default**; add images only when there actually
  are some (no mandatory hero image).
- **`draft`**: starts at **`true`**; flipped to **`false`** only on an explicit
  publish command.

## Tag Vocabulary

**Principle**: tags are **extracted from the article's topic** — there is no
closed list to comply with. They are open-ended: pick the set that best
describes the specific content of the piece. Before inventing a new tag, reuse
an existing one if it fits; but introducing new ids for new topics is perfectly
normal.

Each tag uses the `{ id, label: { en, it } }` shape. The `label` **stays in
English** when it is a proper noun or a technology (e.g. `Next.js`, `Tailwind`);
it is translated when a natural Italian equivalent exists (e.g. `Guide` →
`Guida`).

Real example (article "Release of Tailwind Next.js Starter Blog v2.0"):

```yaml
tags:
  - id: next-js
    label:
      en: Next.js
      it: Next.js
  - id: tailwind
    label:
      en: Tailwind
      it: Tailwind
  - id: guide
    label:
      en: Guide
      it: Guida
  - id: feature
    label:
      en: Feature
      it: Funzionalità
```

Id conventions: **kebab-case**, lowercase (e.g. `next-js`, `app-router`).

## Taboos

**Confidentiality (hard rule)**:

- **Never** reveal client names, secrets or credentials, internal
  URLs/endpoints, or private project details.
- **Anonymize** work projects (no company/client names). Only **personal/open**
  projects may be discussed freely.
- When in doubt, generalize: describe the technical problem without exposing the
  proprietary context.
- In any **example that involves a secret**, never show the real or a plausible
  secret, even as sample *input*. Use an obvious placeholder like
  `<a-very-secret-token>`. (An example demonstrating redaction that leaks a
  real-looking token defeats its own point.)

**Style to avoid**:

- **No em-dashes (`—`)**. They are a clear AI tell. Use commas, colons,
  parentheses, or separate sentences instead.
- **No "AI-style" punchline closers**: avoid the rhetorical "the difference
  between X and Y is never A, it's B" formula and grandiose, self-congratulatory
  wrap-ups. End plainly, ideally on a concrete or self-deprecating note.
- No **hype/marketing** tone ("revolutionary", "game-changer", "the ultimate
  solution").
- No **AI-speak** and empty/generic filler phrases.
- No **clickbait** and no excessive exclamations.
- Avoid **walls of bullet points** used in place of prose: the piece is first of
  all a first-person narrative.

## Examples

There is no reference article yet (this is the first blog). The tone guidance,
however, is precise and draws on two Italian comic authors, used as *flavour*,
not as pastiche — the technical substance always stays serious and correct.

**Reference 1 — Paolo Villaggio's "Fantozzi" books (light touch).** Use as an
occasional seasoning, not the main dish:

- **Tragicomic hyperbole**: technical mishaps (broken builds, night deploys,
  absurd bugs) told with a touch of epic, catastrophic emphasis — but *dosed*,
  never over the top.
- **Unexpected, slightly exaggerated adjectives** used with comic understatement.
- **Self-irony and mild fatalism**: the narrator endures events with comic
  dignity.
- **Register contrast**: lofty/bureaucratic language applied to trivial things,
  the sentence starting serious and tipping into the absurd.

**Reference 2 — Daniele Luttazzi (comic mechanism only, filtered by the
Taboos).** Take the *device*, not the raw register:

- **Non-sequiturs and surreal juxtapositions**: an element that seems totally
  out of context, dropped in to surprise.
- **High erudition mixed with the mundane** for contrast.
- **Sharp, aphoristic one-liners** that land a point.
- **Constraint**: stay within the Taboos above — professional, no gratuitous
  vulgarity, no heavy provocation. Keep only the logical-absurdist comedy, not
  the shock register.

Micro-example of the intended tone (indicative, in Italian as a voice sample).
Note both flavours at work: a marked-but-not-overdone **Fantozzi** touch
(tragicomic hyperbole, register contrast) and a **Luttazzi** device (a surreal
non-sequitur dropped in, plus a sharp aphoristic close):

> Il deploy delle due di notte è fallito con una puntualità mostruosa, di quelle
> che ti fanno rimpiangere di aver scelto l'informatica invece del noleggio di
> pattini a Rimini. Un `500` secco, senza nemmeno la cortesia di uno stack trace
> decente: il server taceva come un impiegato interrogato dal ragioniere capo,
> mentre in sottofondo, non so perché, un tacchino in smoking recitava a memoria
> l'intera documentazione di Kubernetes con l'accento di Danzica. Ho fissato i
> log per un istante (e i log, si sa, sono l'unico luogo in cui la verità e la
> fantascienza vanno a braccetto, seguite a tre metri di distanza da un notaio
> che piange), poi mi sono rimboccato le maniche, perché il bug non si risolve
> da solo, esattamente come la coscienza, il mutuo, e quel container che giura
> di essere "healthy" da quarantatré minuti.

Note: adapt this tone in the Italian version too; in English, find a credible
ironic equivalent without translating the Italian cultural references literally.

### Approved voice samples (from the first article, IT)

Real excerpts the author approved. Use them as calibration for how much irony
and surreal over-specification is "right" in the Italian body.

**Fantozzi register: the word "spettacolare" for a catastrophe:**

> Quella noiosa: infilare qualche kilobyte di markdown dentro un prompt
> interattivo può far terminare la richiesta di botto, che è un modo
> spettacolare di buttare via il lavoro.

**Luttazzi device: a plausible start extended into a precise, over-specified,
faintly absurd image:**

> Io faccio una revisione del manufatto, non del riassunto del manufatto, che è
> la stessa differenza tra leggere un contratto di persona e farselo raccontare
> al telefono da uno sconosciuto che ha imparato da poco la tua lingua mentre
> viaggia su un treno in un tratto con diverse gallerie.

**Self-deprecating close, no translated "you":**

> Sul tono, giudizio sospeso. Io sono solo enormemente sollevato che, lungo la
> strada, non sia finito niente sotto un `rm -rf`.
