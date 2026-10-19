-- v13 — a class level says which stage of school it is, and the senior school exists.
--
-- Every class level looked alike: `name`, `code`, `age_range`, `active`. Nothing said primary, junior or
-- senior, so nothing downstream could tell a JSS pupil from an SSS one — the lesson generator's own
-- `ClassLevel` enum stops at `JSS_3` and gives every class from JSS 1 up the same wording and the same
-- 500-600 word body. The senior school needs the difference stated once, in the data, rather than inferred
-- from a name somewhere.
--
-- `tier` is that statement, with three values and NONE for a row nobody has classified yet (a value the
-- school can leave alone rather than be forced into). The classes that exist keep working without it.

DEFINE FIELD IF NOT EXISTS tier ON class_levels TYPE option<string>
  ASSERT $value IN [NONE, "primary", "junior", "senior"];

-- The rows that are already there. Read them first — a school's own codes win over this guess, and the
-- count either side of the two statements belongs in the deploy note:
--
--   SELECT code, name, tier FROM class_levels ORDER BY code;
UPDATE class_levels SET tier = 'junior' WHERE tier = NONE AND string::starts_with(code, 'jss');
UPDATE class_levels SET tier = 'primary' WHERE tier = NONE
  AND (string::starts_with(code, 'primary') OR string::starts_with(code, 'year'));

-- The senior school: three class levels, the same shape as the junior ones (name, code, age range,
-- active) plus the tier. `code` is the record's id here, which is the convention the junior rows use
-- (`jss_1`), and the ages step one year per class from the junior school's own numbers.
CREATE class_levels:sss_1 SET name = 'SSS 1', code = 'sss_1', age_range = '14-15 years', active = true,
  tier = 'senior';
CREATE class_levels:sss_2 SET name = 'SSS 2', code = 'sss_2', age_range = '15-16 years', active = true,
  tier = 'senior';
CREATE class_levels:sss_3 SET name = 'SSS 3', code = 'sss_3', age_range = '16-17 years', active = true,
  tier = 'senior';

-- Nothing else is needed for the scheme to land on a lesson: `lessons.context` already holds the week's
-- own outline on prod (every one of its 3,413 rows carries one — "Distinguishing wants from needs."), and
-- that is the field the scheme's content cell goes into and the generator reads as its `context`
-- argument. No new field was added for it; see `db/load-sss-scheme.py`.

