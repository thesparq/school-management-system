# SSS 1–3 scheme of work — extracted, not yet loaded

**Nothing here is in the database.** This folder is the review copy: the school reads it, corrects it, and
then it becomes the import. The document is `NEW NERDC SCHEME, 2025.pdf` (428 pages, `pdftotext`-able,
made in Word on 2025-09-27), which the school sent for the senior school.

## What the PDF holds, and what was kept

The PDF holds **JUNIOR SECONDARY ONE–THREE** and **SENIOR SECONDARY ONE–THREE**, each with a table per
subject per term. This folder keeps **SSS 1–3 for the 18 subjects the school asked for**.

| Subject | SSS 1 | SSS 2 | SSS 3 |
|---|---|---|---|
| Agricultural Science | 3 · 39 | 3 · 37 | 1 · 14 |
| Biology | 3 · 39 | 3 · 39 | 1 · 13 |
| Chemistry | 3 · 39 | 3 · 39 | 3 · 39 |
| Christian Religious Studies | 3 · 39 | 3 · 39 | 1 · 13 |
| Commerce | 3 · 39 | 3 · 38 | 1 · 13 |
| Digital Technologies | 3 · 30 | 3 · 33 | 3 · 32 |
| Economics | 3 · 39 | 3 · 38 | 2 · 27 |
| English Language | 3 · 39 | 3 · 40 | 2 · 25 |
| Financial Accounting | 3 · 39 | 3 · 34 | 1 · 10 |
| Food and Nutrition | 3 · 39 | 3 · 39 | 2 · 26 |
| Further Mathematics | 3 · 29 | 3 · 39 | 2 · 15 |
| Geography | 3 · 39 | 3 · 37 | 1 · 14 |
| Government | 3 · 39 | 3 · 38 | 2 · 20 |
| History | 3 · 39 | 3 · 39 | 3 · 39 |
| Literature in English | 3 · 36 | 3 · 39 | 2 · 22 |
| Mathematics | 3 · 38 | 3 · 36 | 2 · 26 |
| Physics | 3 · 39 | 3 · 37 | 1 · 13 |
| Visual Arts | 3 · 39 | 3 · 39 | 2 · 26 |


**1,746 weeks in total, 1,096 of them teaching weeks** (the other 650 are the terms' own midterm, break,
revision, examination and closing weeks — kept, because they are the shape of a term, and tagged so the
loader can leave them out).

SSS 3 is a short year in this document, and deliberately: it is the examination year, so most subjects
carry one or two terms of topics and then revision/mock material. Where the PDF gives no table at all for
an SSS 3 term, none is written here — see the questions below.

## The files

| File | What it is |
|---|---|
| `schemes.json` | the data: subject → class → term → weeks, each week `{week, topic, content, kind}` |
| `sss1.md`, `sss2.md`, `sss3.md` | the same tables, readable, one per class |
| `contexts.md` | what the senior tier means for lesson generation, per subject, and how the maths is written |
| `extract_sss.py` | how these were read out of the PDF — re-runnable, no row hand-edited |
| `../../db/schema-v13-class-tier.surql` | the tier, the three senior classes, `lessons.content_outline` |
| `../../db/load-sss-scheme.py` | turns this folder's JSON into subjects, edges and lessons |

```sh
python3 extract_sss.py "/path/to/NEW NERDC SCHEME, 2025.pdf"   # rewrites schemes.json and the three .md
```

It reads the PDF with `pdftotext -layout` and parses the fixed-width tables. The PDF is inconsistent in
ways the parser has to know about (a term heading can be `Second Term` or `SS2 – First Term`; a subject
heading can be missing its class or its `SCHEME OF WORK`; the column headings `Content` / `Content
Breakdown` / `Breakdown` do not sit where the rows put their text; tables run on across page breaks).
Those cases are listed at the top of the script. **A row can be wrong because the PDF is wrong or
because the parser misread it — that is exactly what this review is for.**

## Names: what the school asked for, what the document calls it

| Asked for | In the document | Kept as |
|---|---|---|
| English | `ENGLISH STUDIES` (SSS 1), `ENGLISH LANGUAGE` (SSS 2–3), and one `SSS3 ENGLISH STUDIES` table | **English Language** |
| History | `NIGERIAN HISTORY` | **History** |
| Computer | `DIGITAL TECHNOLOGIES` (the new scheme's name for it) | **Computer Studies** |
| CRS | `CHRISTIAN RELIGIOUS STUDIES` | **Christian Religious Studies** |
| Literature | `LITERATURE IN ENGLISH` (also written `LITERATURE-IN-ENGLISH SCHEMES`) | **Literature in English** |
| Visual Art | `VISUAL ARTS` | **Visual Arts** |
| Food Nutrition | `FOOD AND NUTRITION` | **Food and Nutrition** |
| Agricultural science | `AGRICULTURAL SCIENCE` | **Agricultural Science** |
| Further mathematics | `FURTHER MATHEMATICS` | **Further Mathematics** |

The rest (Mathematics, Chemistry, Physics, Biology, Government, Financial Accounting, Economics,
Commerce, Geography) are named as asked. **Yoruba is parked**, not dropped: the PDF has no Yoruba table at
all (nothing anywhere in its 428 pages), so there is nothing to load until the school sends one.

## What the school decided (2026-10-19)

| Question | Answer |
|---|---|
| Yoruba | leave it out for now |
| Computer | call it **Computer Studies** |
| History | the same subject; use **History** |
| SSS 3's short year | keep it as the document has it |
| Which subjects where | **all subjects for all classes** (no streaming) |
| The tier | build it, and make it robust for the calculation subjects — equations want LaTeX |


## The tier — so senior lessons are not junior lessons (built)

Every class level in the database looked alike: `class_levels` carried `name`, `code`, `age_range`,
`active`. Nothing said primary, junior or senior, and the lesson generator's own `ClassLevel` enum stops at
`JSS_3`, whose age-worded branches treat every class from JSS 1 up identically. So a senior lesson would
have come out worded like a junior one.

`db/schema-v13-class-tier.surql` settles it:

* **`class_levels.tier`** — `primary` / `junior` / `senior`, or NONE for a row nobody has classified. The
  rows that exist are backfilled by their codes (`jss*` junior, `primary*`/`year*` primary).
* **SSS 1, SSS 2, SSS 3** — the three senior classes, `tier = 'senior'`, ages `14-15` / `15-16` / `16-17`
  years (one year per class, the pattern the junior rows use; the school can change the numbers).
* **`lessons.content_outline`** — the week's outline from the scheme ("Definition, history, branches, and
  importance of chemistry"), so a lesson row carries both what it is and what it must cover.

The generator side is the other half, and it is a different repository: its `ClassLevel` enum needs
`SSS_1`, `SSS_2`, `SSS_3` and its prompt needs the senior branch. `contexts.md` is that branch written out,
per subject — including the **maths convention**: senior calculation subjects emit LaTeX (`$…$` inline,
`$$…$$` display) and the app typesets it (see the maths section below).

## The maths the calculation subjects need (built)

A senior lesson body carries equations, and the app now renders them instead of showing the source:

* **KaTeX** (0.16.11, MIT) is vendored under `roc-frontend/www/katex/` — the two scripts and the stylesheet,
  plus the `.woff2` fonts the stylesheet names (296 KB of fonts; no CDN, because the app has to typeset
  maths on a school network). `www/index.html` loads them with `defer` and `typesetMath(el)` runs after a
  lesson, a question bank or an answer form is rendered, converting `$…$`, `$$…$$`, `\(…\)` and `\[…\]`.
  A broken formula stays visible as its own source (`throwOnError: false`) rather than blanking the lesson,
  and a page without the scripts (a DOM stub in a test) leaves the LaTeX readable.
* `tests/e2e/math_render_check.cjs` is the check: it writes a lesson whose body carries inline formula,
  a display formula, an MCQ and a model answer, drives Chromium to it, and asserts KaTeX typeset them (7
  checks). It was also eyeballed: `1011_2 = 1 × 2³ + 0 × 2² + 1 × 2¹ + 1 × 2⁰ = 11_10` rendered as a display
  equation with the subscripts and superscripts in place.


## Loading it (the script, and what it wrote on the sandbox)

`db/load-sss-scheme.py` turns `schemes.json` into rows. Order, and every step is skipped when the row is
already there, so a re-run is a no-op:

1. **subjects** — one per subject under a readable id (`subjects:chemistry`); an existing subject of the
   same name is reused (Agricultural Science already is).
2. **has_subject** — the curriculum edge from each senior class to each subject: 18 × 3 = 54, because the
   school's answer was "all subjects for all classes".
3. **terms** — the scheme says First/Second/Third; the school's own term rows have its own names, so
   `--terms Second=terms:summer_term` says which record a scheme term means (`terms:first_term` and
   friends are created when nothing matches).
4. **lessons** — one per **teaching** week (1,096 of the 1,746), `topic_title` and `content_outline` from
   the file, `content` left empty for the generator, `slug` = `<subject>-<class>-<term>-w<week>`.
   `--include-non-teaching` also makes rows for midterm/break/revision/exam weeks.

On the sandbox it ran clean: 54 edges, 3 terms, 1,096 lessons, then `0 to create` on the second run, and a
sample row read back as *SSS 1 · Chemistry · First Term · week 1 · "Introduction to Chemistry"* with the
outline `"Definition, history, branches, and importance of chemistry"`.

```sh
python3 db/schema-v13-class-tier.surql                       # via the usual /sql call, or Dokploy's own step
python3 db/load-sss-scheme.py --dry-run                      # what it would write
python3 db/load-sss-scheme.py --terms First=terms:noel_term  # the real run
```

**The sandbox was reset afterwards, deliberately**: the loader's 1,096 lessons change what an unscoped
lesson list returns, and `e2e_assessments.cjs` picks the fixture lesson by name from that list. The tier
(and the three senior class levels) stayed, because they change nothing else. Run the loader whenever the
senior data is wanted.

**One thing the load surfaced — `LIMIT 50` with no tie-break.** `/api/teacher/lessons` (the picker's list)
answers `ORDER BY week LIMIT 50`. With ~1,100 lessons in the database, "week 1" alone fills the whole page,
the rows that come back are whatever the database returns first, and a teacher's own list (assignments ×
terms × weeks) can exceed 50 and quietly lose entries. The LMS drill-down is unaffected (it passes
class/subject/term), so this only bites the unprefixed picker. Worth a follow-up: order by something total
(subject, then week) and give the picker a search or a term step rather than a silent cap.


## Also extracted, but not asked for

The senior section of the PDF also carries Solar Photovoltaic Installation & Maintenance, Fashion Design
& Garment Making, Computer Hardware and GSM Repairs, Horticulture and Crop Production, Livestock Farming,
Beauty and Cosmetology, Catering and Craft Practice, Marketing, Technical Drawing, Citizenship and
Heritage Studies — and, under Literature, the **WAEC recommended texts for 2026–2030**. The first ten are
not extracted here (ask and they will be); the WAEC text list is in `contexts.md` for the Literature
block.
