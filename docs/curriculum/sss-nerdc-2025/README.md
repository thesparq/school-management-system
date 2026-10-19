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
| `contexts.md` | what the senior tier means for lesson generation, per subject |
| `extract_sss.py` | how these were read out of the PDF — re-runnable, no row hand-edited |

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
| Computer | `DIGITAL TECHNOLOGIES` (the new scheme's name for it) | **Digital Technologies** |
| CRS | `CHRISTIAN RELIGIOUS STUDIES` | **Christian Religious Studies** |
| Literature | `LITERATURE IN ENGLISH` (also written `LITERATURE-IN-ENGLISH SCHEMES`) | **Literature in English** |
| Visual Art | `VISUAL ARTS` | **Visual Arts** |
| Food Nutrition | `FOOD AND NUTRITION` | **Food and Nutrition** |
| Agricultural science | `AGRICULTURAL SCIENCE` | **Agricultural Science** |
| Further mathematics | `FURTHER MATHEMATICS` | **Further Mathematics** |

The rest (Mathematics, Chemistry, Physics, Biology, Government, Financial Accounting, Economics,
Commerce, Geography) are named as asked.

## What needs the school's answer before this can be loaded

1. **Yoruba is not in this PDF.** There is no Yoruba (or any Nigerian-language) table anywhere in the 428
   pages — `Yoruba` appears only inside other subjects' content. The 18 above are everything the document
   has that the school asked for. Yoruba needs either a second document or the school's own table.
2. **Computer = Digital Technologies** is an assumption: the new NERDC scheme renamed the subject, and
   `DIGITAL TECHNOLOGIES` is the only computer-subject table the senior section has. Confirm, or send the
   name the school uses.
3. **SSS 3's missing terms.** Chemistry, History, and Digital Technologies have all three terms; most SSS 3
   subjects have one or two. Keep as the document has it (the third term is after WAEC/NECO), or add the
   school's own revision plan for those terms?
4. **The three new classes' age ranges.** Proposed: SSS 1 `14-15 years`, SSS 2 `15-16 years`, SSS 3
   `16-17 years` (the usual ages for the senior school). The existing rows in the database step one year per
   class from JSS 1 = 10-11, which would make SSS 1 = 13-14 — the school's own numbers win.
5. **The subjects offered where.** A senior school streams (Science / Arts / Commercial), so the school may
   not want all 18 subjects on all three classes. The scheme data is per subject and does not assume a
   stream; the load does.
6. **The subject codes** for the new `subjects` rows (the existing rows use `AGR`, `BSC`, … — the school may
   have its own list).

## The tier — so senior lessons are not junior lessons

Every class level in the database looks alike today: `class_levels` carries `name`, `code`, `age_range`,
`active`. Nothing says junior or senior, and the lesson generator's own `ClassLevel` enum stops at `JSS_3`
(`v1/johnethel-school-lesson-generator/baml_src/lesson.baml`), whose age-worded branches treat every
class from JSS 1 up identically. So a senior lesson today would come out worded like a JSS lesson.

**Proposal (not applied):** one field on `class_levels`, `tier`, and the three senior classes carrying
`"senior"`.

```surql
-- db/schema-v13-class-tier.surql  (to be written and applied only on the school's go-ahead)
DEFINE FIELD IF NOT EXISTS tier ON class_levels TYPE option<string>
  ASSERT $value IN [NONE, "primary", "junior", "senior"];

-- backfill the classes that exist (read them first: the schools's own rows and codes win over this guess)
UPDATE class_levels SET tier = 'junior' WHERE string::starts_with(code, 'jss');
UPDATE class_levels SET tier = 'primary' WHERE string::starts_with(code, 'primary') OR string::starts_with(code, 'year');

-- the new senior classes
CREATE class_levels:sss_1 SET name = 'SSS 1', code = 'sss_1', age_range = '14-15 years', active = true, tier = 'senior';
CREATE class_levels:sss_2 SET name = 'SSS 2', code = 'sss_2', age_range = '15-16 years', active = true, tier = 'senior';
CREATE class_levels:sss_3 SET name = 'SSS 3', code = 'sss_3', age_range = '16-17 years', active = true, tier = 'senior';
```

The generator side is the other half, and it is a different repository: its `ClassLevel` enum needs
`SSS_1`, `SSS_2`, `SSS_3`, and its prompt needs the senior branch that the tier stands for —
exam-standard wording, quantitative treatment, worked examples, WAEC/NECO past-question practice, longer
content. `contexts.md` is that branch written out per subject, ready to hand over as the generator's
`context` argument.

## How this lands in the database (proposal, for approval)

The app's model is already the right shape for a scheme — a subject is offered in a class through a
`has_subject` edge, and a lesson hangs off that edge:

```
class_levels:jss_1 ──has_subject──▶ subjects:agricultural_science ──▶ lessons {week, term, topic_title, content}
```

So loading this scheme is:

1. `class_levels`: the three rows above.
2. `subjects`: one row per new subject (`Agricultural Science` and `Mathematics` already exist in the
   fixture — reuse rather than duplicate).
3. `has_subject`: one edge per class level × subject the school offers there.
4. `lessons`: one row per **teaching** week — `has_subject` = the edge, `term` = the school's term record,
   `week` = the week number, `topic_title` = the topic, `slug` = a slug of it, `duration_mins` = 40, and
   `content` left empty for the generator to fill (the same field it already writes).

One addition is wanted for that to work well: the week's **`content` cell is the generation context** —
the things the lesson must cover, which the PDF already spells out per week ("Definition, history,
branches, and importance of chemistry"). Two ways to keep it:

* **a new field on the lesson row**, e.g. `content_outline (option<string>)`, so a row carries its own
  topic *and* what that topic covers; or
* a separate `scheme_of_work` table keyed by class/subject/term/week, with the `lessons` rows generated
  from it.

The first is smaller and keeps one row per thing the school teaches; the second keeps the school's
curriculum separable from its lessons. Either way the generator gets `topic` + `content_outline` as its
`topic` and `context` arguments, which is exactly what its `GenerateNigerianLesson` signature takes.

## Also extracted, but not asked for

The senior section of the PDF also carries Solar Photovoltaic Installation & Maintenance, Fashion Design
& Garment Making, Computer Hardware and GSM Repairs, Horticulture and Crop Production, Livestock Farming,
Beauty and Cosmetology, Catering and Craft Practice, Marketing, Technical Drawing, Citizenship and
Heritage Studies — and, under Literature, the **WAEC recommended texts for 2026–2030**. The first ten are
not extracted here (ask and they will be); the WAEC text list is in `contexts.md` for the Literature
block.
