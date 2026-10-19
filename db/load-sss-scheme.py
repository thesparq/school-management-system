#!/usr/bin/env python3
"""Load the school's SSS 1-3 scheme of work into SurrealDB.

    python3 db/load-sss-scheme.py --dry-run
    python3 db/load-sss-scheme.py --terms First=terms:noel_term --terms Second=terms:summer_term

The scheme itself is `docs/curriculum/sss-nerdc-2025/schemes.json` (see that folder's README: it is the
review copy the school signs off; this script is what turns it into rows). Nothing here invents content —
topic and content come from the file.

What it writes, in order, and only where the row is missing (so a re-run is a no-op):

1. **subjects** — one per subject, reused when a subject of that name already exists (Agricultural
   Science already does). The codes are the ones in `SUBJECT_CODES`; the school may want its own.
2. **has_subject** — the curriculum edge from each class level to each subject, which is what makes a
   subject offered in a class ("all subjects for all classes", the school's call on 2026-10-19).
3. **terms** — the scheme says First/Second/Third; the *school's* term rows are named by its own
   calendar, so `--terms Second=terms:summer_term` says which record a scheme term means. Without it, a
   `terms:first_term` / `second_term` / `third_term` row is created if the name has no match.
4. **lessons** — one per week, with `topic_title` and `content_outline` (the week's own content cell,
   which is the context the lesson generator is handed) and `content` left empty for the generator to
   fill. Teaching weeks only unless `--include-non-teaching` is given: a school's midterm, break and
   examination weeks are the term's shape, not lessons.

The class levels themselves come from `db/schema-v13-class-tier.surql`, not from here — apply that first
(this script refuses to run without `sss_1`, `sss_2` and `sss_3`).
"""
import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request

SUBJECT_CODES = {
    'Agricultural Science': 'AGR',
    'Biology': 'BIO',
    'Chemistry': 'CHM',
    'Christian Religious Studies': 'CRS',
    'Commerce': 'COM',
    'Computer Studies': 'CMP',
    'Economics': 'ECO',
    'English Language': 'ENG',
    'Financial Accounting': 'FIN',
    'Food and Nutrition': 'FNT',
    'Further Mathematics': 'FMT',
    'Geography': 'GEO',
    'Government': 'GOV',
    'History': 'HIS',
    'Literature in English': 'LIT',
    'Mathematics': 'MTH',
    'Physics': 'PHY',
    'Visual Arts': 'VAR',
}
SCHEME_TERMS = {'FIRST': 'First', 'SECOND': 'Second', 'THIRD': 'Third'}
CLASS_SLUG = {'SS1': 'sss-1', 'SS2': 'sss-2', 'SS3': 'sss-3'}
CLASS_CODE = {'SS1': 'sss_1', 'SS2': 'sss_2', 'SS3': 'sss_3'}


def literal(text):
    """A SurrealQL string literal: quoted, with the characters that would end it escaped."""
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def as_record(rid):
    """A record id as SurrealQL needs it written.

    `subjects:chemistry` can be written as-is, but `subjects:computer-studies` cannot: a key that is not a
    bare word is parsed as an expression (the database reads the hyphen as subtraction), so the key goes in
    backticks. Ids come back from the database without them, which is why every statement below passes them
    through here rather than interpolating a string it took from a response — or built itself.
    """
    table, _, key = rid.partition(':')
    if not key:
        raise SystemExit(f"not a record id: {rid!r}")
    # the database prints an id that needs quoting with its backticks already on (`subjects:`a-b``),
    # and hands back a bare one otherwise, so take them off before deciding how to write it
    key = key.strip('`')
    bare = re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key)
    return f"{table}:{key}" if bare else f"{table}:`{key}`"


def slugify(text):
    slug = re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
    return slug[:60].strip('-')


class Db:
    def __init__(self, url, user, password, ns, db, dry_run):
        self.url, self.ns, self.db, self.dry_run = url, ns, db, dry_run
        self.auth = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.writes = 0

    def query(self, statement):
        request = urllib.request.Request(
            self.url, data=statement.encode(), method='POST',
            headers={'Authorization': f'Basic {self.auth}', 'surreal-ns': self.ns,
                     'surreal-db': self.db, 'Accept': 'application/json',
                     'Content-Type': 'text/plain'})
        try:
            with urllib.request.urlopen(request) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            raise SystemExit(f"the database answered {error.code}: {error.read().decode()[:400]}")

    def rows(self, statement):
        """The rows of a single-statement read."""
        blocks = self.query(statement)
        for block in blocks:
            if block.get('status') != 'OK':
                raise SystemExit(f"{block.get('status')}: {str(block.get('result'))[:300]}")
        return blocks[-1].get('result') or []

    def write(self, statement):
        """One statement that changes something; a dry run counts it instead of running it."""
        self.writes += 1
        if self.dry_run:
            return []
        blocks = self.query(statement)
        for block in blocks:
            if block.get('status') != 'OK':
                raise SystemExit(f"the database refused a write: {str(block.get('result'))[:300]}\n{statement[:300]}")
        return blocks[-1].get('result') or []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    here = os.path.dirname(os.path.abspath(__file__))
    parser.add_argument('--schemes', default=os.path.join(here, '..', 'docs', 'curriculum', 'sss-nerdc-2025', 'schemes.json'))
    parser.add_argument('--url', default=os.environ.get('SURREAL_URL', 'http://127.0.0.1:8002/sql'))
    parser.add_argument('--user', default=os.environ.get('SURREAL_USER', 'root'))
    parser.add_argument('--pass', dest='password', default=os.environ.get('SURREAL_PASS', 'root'))
    parser.add_argument('--ns', default=os.environ.get('SURREAL_NS', 'main'))
    parser.add_argument('--db', default=os.environ.get('SURREAL_DB', 'lessons'))
    parser.add_argument('--terms', action='append', default=[], metavar='First=terms:noel_term',
                        help='which term record a scheme term means; repeatable')
    parser.add_argument('--include-non-teaching', action='store_true',
                        help='also make lessons for midterm, break, revision and examination weeks')
    parser.add_argument('--only', action='append', default=[], help='load only this subject (repeatable)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    schemes = json.load(open(args.schemes))
    db = Db(args.url, args.user, args.password, args.ns, args.db, args.dry_run)
    print(f"{'DRY RUN: ' if args.dry_run else ''}{args.url} ns={args.ns} db={args.db} — {len(schemes)} subjects from {os.path.relpath(args.schemes)}")

    levels = {row['code']: row for row in
              db.rows("SELECT id, name, code, tier FROM class_levels WHERE code IN ['sss_1','sss_2','sss_3'];")
              }
    missing = [c for c in ('sss_1', 'sss_2', 'sss_3') if c not in levels]
    if missing:
        raise SystemExit(f"class levels missing: {', '.join(missing)} — apply db/schema-v13-class-tier.surql first")
    print(f"  class levels: " + ", ".join(f"{levels[c]['name']} ({levels[c].get('tier')})" for c in ('sss_1', 'sss_2', 'sss_3')))
    wanted = [s for s in schemes if not args.only or s in args.only]
    unknowns = [s for s in args.only if s not in schemes]
    if unknowns:
        raise SystemExit(f"not in the scheme file: {', '.join(unknowns)}")

    # 1. subjects — created under a readable id (`subjects:chemistry`), the convention the existing
    #    subjects use; an existing row with the same name is reused whatever its id looks like.
    existing = {row['name'].strip().lower(): row for row in db.rows('SELECT id, name, code FROM subjects;')}
    subject_ids = {}
    for name in wanted:
        found = existing.get(name.strip().lower())
        if found:
            subject_ids[name] = found['id']
            print(f"  subject {name}: reusing {found['id']} ({found['code']})")
            continue
        code = SUBJECT_CODES.get(name, name[:3].upper())
        rid = f'subjects:{slugify(name)}'
        rows = db.write(f"CREATE {as_record(rid)} SET name = {literal(name)}, code = {literal(code)}, active = true;")
        subject_ids[name] = rows[0]['id'] if rows else rid
        print(f"  subject {name}: create {as_record(subject_ids[name])} ({code})")
    if len(set(subject_ids.values())) != len(wanted):
        raise SystemExit("two subjects resolved to one record — check the names in the scheme file")

    # 2. the curriculum edges, from the class-level records themselves (never from a composed id: an
    #    id the database does not have makes RELATE quietly create it, which is how a load can land on a
    #    graph nobody can see).
    edges = {(row['in'], row['out']): row['id'] for row in db.rows('SELECT id, `in`, out FROM has_subject;')}
    edge_ids, edges_before = {}, 0
    for name in wanted:
        for cls in ('SS1', 'SS2', 'SS3'):
            level = levels[CLASS_CODE[cls]]['id']
            key = (level, subject_ids[name])
            if key in edges:
                edge_ids[(name, cls)] = edges[key]
                edges_before += 1
                continue
            rows = db.write(f"RELATE {as_record(level)}->has_subject->{as_record(subject_ids[name])};")
            if rows and rows[0].get('in') != level:
                raise SystemExit(f"RELATE answered an edge from {rows[0].get('in')}, expected {level}")
            edge_ids[(name, cls)] = rows[0]['id'] if rows else f'has_subject:{slugify(name)}-{cls.lower()}'
    print(f"  curriculum edges: {len(edge_ids)} in place for the subjects loaded "
          f"({edges_before} of them already existed, {len(edge_ids) - edges_before} to create)")

    # 3. terms
    asked = {}
    for pair in args.terms:
        if '=' not in pair:
            raise SystemExit(f"--terms wants Term=record, got {pair!r}")
        term, record = pair.split('=', 1)
        asked[term.strip().title()] = record if record.startswith('terms:') else f'terms:{slugify(record)}'
    term_ids = {}
    for order, term in enumerate(('First', 'Second', 'Third'), start=1):
        if term in asked:
            wanted_term = asked[term]
            rows = db.rows(f"SELECT id FROM {as_record(wanted_term)};")
            if not rows:
                db.write(f"CREATE {as_record(wanted_term)} SET name = {literal(term + ' Term')}, sort_order = {order}, active = true;")
            term_ids[term] = wanted_term
        else:
            found = db.rows(f"SELECT id FROM terms WHERE string::lowercase(name) CONTAINS {literal(term.lower())} LIMIT 1;")
            term_ids[term] = found[0]['id'] if found else f'terms:{slugify(term)}_term'
            if not found:
                db.write(f"CREATE {as_record(term_ids[term])} SET name = {literal(term + ' Term')}, sort_order = {order}, active = true;")
    print("  terms: " + ", ".join(f"{t}={as_record(i)}" for t, i in term_ids.items()))

    # 4. lessons
    lessons, skipped = 0, 0
    have = {(row['has_subject'], row['week']) for row in db.rows('SELECT has_subject, week FROM lessons;')}
    for name in wanted:
        for cls, terms in schemes[name].items():
            edge = edge_ids[(name, cls)]
            for scheme_term, block in terms.items():
                term = SCHEME_TERMS[scheme_term]
                for week in block['weeks']:
                    if week['kind'] != 'teaching' and not args.include_non_teaching:
                        skipped += 1
                        continue
                    number = int(re.match(r'\d+', week['week']).group())
                    if (edge, number) in have:
                        skipped += 1
                        continue
                    slug = f"{slugify(name)}-{CLASS_SLUG[cls]}-{term.lower()}-w{number}"
                    db.write(
                        f"CREATE lessons SET has_subject = {as_record(edge)}, term = {as_record(term_ids[term])}, "
                        f"week = {number}, topic_title = {literal(week['topic'])}, "
                        f"slug = {literal(slug)}, duration_mins = 40, active = true, "
                        f"content_outline = {literal(week['content'])};")
                    lessons += 1
    print(f"  lessons: {lessons} to create, {skipped} weeks skipped (non-teaching or already there)")
    print(f"{'would write' if args.dry_run else 'wrote'} {db.writes} statement(s)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
