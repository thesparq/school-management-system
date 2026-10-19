#!/usr/bin/env python3
"""Extract the senior-secondary scheme of work from the school's NERDC 2025 PDF.

    python3 extract_sss.py "/path/to/NEW NERDC SCHEME, 2025.pdf"

Writes beside this file: `schemes.json` (the data) and `sss1.md`, `sss2.md`, `sss3.md` (the same
tables, readable). The PDF holds JSS 1-3 and SSS 1-3 for about two dozen subjects; this keeps SSS 1-3
for the subjects the school asked for (`REQUESTED`) and drops the rest.

The document is a Word-made PDF whose tables `pdftotext -layout` renders as fixed-width text. The
quirks this survives, all of them in the file:

* a term heading can be `FIRST TERM`, `First Term`, `SS2 - First Term`, and once
  `THIRD TERM (Pre-Exam/Break Term)`;
* a subject heading can carry its class (`SS1 MATHEMATICS SCHEME OF WORK`), not carry it
  (`SOLAR PHOTOVOLTAIC INSTALLATION & MAINTENANCE`), be hyphenated with a plural
  (`SS2 LITERATURE-IN-ENGLISH SCHEMES OF WORK`), or be a bare all-caps title line;
* the third column is headed `Content`, `Content Breakdown` or `Breakdown`, and none of those columns
  sit where the data rows put their text — so the topic/content split is derived from the table's own
  lines (where its wide gaps line up), with the header as the fallback;
* a table runs on across page breaks, with a bare page number between its rows, and repeats its
  subject title and header on the next page;
* weeks are `1`, `1.`, `1 & 2`, `11–13`, or `11–` with the `13` on the line below.

No row is hand-edited: the output is what the parser read, so re-running this against a corrected
PDF yields corrected data. Each row is tagged `teaching`, or the kind of non-teaching week it is
(`assessment`, `break`, `revision`, `admin`).
"""
import json
import os
import re
import subprocess
import sys
from collections import OrderedDict

# The senior subjects the school asked for, and the names this document gives them per class.
REQUESTED = OrderedDict([
    ('English Language',             {'SS1': ['ENGLISH STUDIES'], 'SS2': ['ENGLISH LANGUAGE'], 'SS3': ['ENGLISH LANGUAGE', 'ENGLISH STUDIES']}),
    ('Mathematics',                  {'SS1': ['MATHEMATICS'], 'SS2': ['MATHEMATICS'], 'SS3': ['MATHEMATICS']}),
    ('Chemistry',                    {'SS1': ['CHEMISTRY'], 'SS2': ['CHEMISTRY'], 'SS3': ['CHEMISTRY']}),
    ('Physics',                      {'SS1': ['PHYSICS'], 'SS2': ['PHYSICS'], 'SS3': ['PHYSICS']}),
    ('Biology',                      {'SS1': ['BIOLOGY'], 'SS2': ['BIOLOGY'], 'SS3': ['BIOLOGY']}),
    ('Further Mathematics',          {'SS1': ['FURTHER MATHEMATICS'], 'SS2': ['FURTHER MATHEMATICS'], 'SS3': ['FURTHER MATHEMATICS']}),
    ('Government',                   {'SS1': ['GOVERNMENT'], 'SS2': ['GOVERNMENT'], 'SS3': ['GOVERNMENT']}),
    ('History',                      {'SS1': ['NIGERIAN HISTORY'], 'SS2': ['NIGERIAN HISTORY'], 'SS3': ['NIGERIAN HISTORY']}),
    ('Financial Accounting',         {'SS1': ['FINANCIAL ACCOUNTING'], 'SS2': ['FINANCIAL ACCOUNTING'], 'SS3': ['FINANCIAL ACCOUNTING']}),
    ('Economics',                    {'SS1': ['ECONOMICS'], 'SS2': ['ECONOMICS'], 'SS3': ['ECONOMICS']}),
    ('Commerce',                     {'SS1': ['COMMERCE'], 'SS2': ['COMMERCE'], 'SS3': ['COMMERCE']}),
    ('Christian Religious Studies',  {'SS1': ['CHRISTIAN RELIGIOUS STUDIES'], 'SS2': ['CHRISTIAN RELIGIOUS STUDIES'], 'SS3': ['CHRISTIAN RELIGIOUS STUDIES']}),
    ('Literature in English',        {'SS1': ['LITERATURE IN ENGLISH'], 'SS2': ['LITERATURE IN ENGLISH'], 'SS3': ['LITERATURE IN ENGLISH']}),
    ('Visual Arts',                  {'SS1': ['VISUAL ARTS'], 'SS2': ['VISUAL ARTS'], 'SS3': ['VISUAL ARTS']}),
    ('Agricultural Science',         {'SS1': ['AGRICULTURAL SCIENCE'], 'SS2': ['AGRICULTURAL SCIENCE'], 'SS3': ['AGRICULTURAL SCIENCE']}),
    ('Food and Nutrition',           {'SS1': ['FOOD AND NUTRITION'], 'SS2': ['FOOD AND NUTRITION'], 'SS3': ['FOOD AND NUTRITION']}),
    ('Digital Technologies',         {'SS1': ['DIGITAL TECHNOLOGIES'], 'SS2': ['DIGITAL TECHNOLOGIES'], 'SS3': ['DIGITAL TECHNOLOGIES']}),
    ('Geography',                    {'SS1': ['GEOGRAPHY'], 'SS2': ['GEOGRAPHY'], 'SS3': ['GEOGRAPHY']}),
])
TERMS = ['FIRST', 'SECOND', 'THIRD']
TERM_TITLE = {'FIRST': 'First term', 'SECOND': 'Second term', 'THIRD': 'Third term'}
CLASS_TITLE = {'SS1': 'SSS 1', 'SS2': 'SSS 2', 'SS3': 'SSS 3'}

# Lines the parser recognises.
CLASS_MARK = re.compile(r'^\s*(JUNIOR|SENIOR) SECONDARY (ONE|TWO|THREE) SCHEME OF WORK\s*$')
SUBJ = re.compile(r'^\s*(?:(SSS?|SS+)\s*([123])\s+)?(.+?)\s+SCHEME[S]?\s+OF\s+WORK\s*$', re.I)
TERM = re.compile(r'^\s*(?:SSS?\s*[123]\s*[\u2013-]\s*)?(FIRST|SECOND|THIRD)\s+TERM\s*(?:\(.*\))?\s*$', re.I)
TERM_CLS = re.compile(r'^\s*SSS?\s*([123])\s*[\u2013-]', re.I)
THEME = re.compile(r'^\s*Theme\s*:\s*(.+?)\s*$', re.I)
HEADER = re.compile(r'^\s*WEEK\s+.*TOPIC\s*.*$', re.I)
WEEK_START = re.compile(r'^\s*(\d{1,2}(?:\s*(?:[.&]\s*\d{1,2}|[\u2013-]\s*\d{1,2})?)?)\s*[.&]?\s+(?=\S)')
WEEK_ONLY = re.compile(r'^\s*(\d{1,2})\s*[\u2013-]\s*$')
BARE = re.compile(r'^\s*\d{1,2}\s*$')
SKIP = re.compile(r'^\s*$|^\s*\d{1,3}\s*$')
CLASS_OF = {'ONE': 'SS1', 'TWO': 'SS2', 'THREE': 'SS3'}
NON_TEACHING = [(r'midterm break|mid-term break', 'break'), (r'midterm|mid-term', 'assessment'),
                (r'break', 'break'), (r'examination|exam\b|exams', 'assessment'),
                (r'revision|review', 'revision'),
                (r'closing|vacation|open day|welcome test|test\b', 'admin')]


def norm(text):
    return re.sub(r'\s+', ' ', text.replace('\u00a0', ' ')).strip()


def is_title(line):
    """A heading the document wrote without 'SCHEME OF WORK': a bare all-caps title line."""
    s = line.strip()
    return (5 <= len(s) <= 70 and not re.search(r'[a-z]', s) and re.search(r'[A-Z]{3}', s)
            and len(s.split()) >= 2 and not re.match(r'^(WEEK|FIRST|SECOND|THIRD)\b', s)
            and 'TERM' not in s.upper() and not re.search(r'SCHEME', s, re.I))


def heading_index(lines):
    """Every senior subject heading, as (line index, class, subject), in document order."""
    ranges, current = [], None
    for i, line in enumerate(lines):
        mark = CLASS_MARK.match(line)
        if mark:
            if current:
                ranges.append([current[0], i])
            current = [i, len(lines)] if mark.group(1) == 'SENIOR' else None
    if current:
        ranges.append(current)

    headings = []
    for start, end in ranges:
        class_here = CLASS_OF[CLASS_MARK.match(lines[start]).group(2)]
        for i in range(start, end):
            mark = SUBJ.match(lines[i])
            if mark:
                name = norm(mark.group(3))
                if 'SECONDARY' in name.upper() or len(name) > 70:
                    continue
                subject = re.sub(r'\s+', ' ', name.upper().replace('-', ' ')).strip()
                headings.append((i, f"SS{mark.group(2)}" if mark.group(2) else class_here, subject))
            elif is_title(lines[i]):
                title = lines[i].strip()
                prefixed = re.match(r'^SSS?\s*([123])\s+(.*)$', title, re.I)
                if prefixed:
                    headings.append((i, f"SS{prefixed.group(1)}", prefixed.group(2).upper()))
                else:
                    headings.append((i, class_here, title.upper()))
    return ranges, headings


def split_rows(body, target):
    """One term table's rows. The topic/content boundary is read from the table's own lines."""
    candidates = []
    for line in body:
        week = WEEK_START.match(line)
        if not week:
            continue
        first = re.search(r'\S', line[week.end():])
        if not first:
            continue
        gap = re.search(r'\s{3,}', line[week.end() + first.start():])
        if gap:
            candidates.append(week.end() + first.start() + gap.end())
    boundary = None
    if len(candidates) >= 3 and max(candidates) - min(candidates) <= 14:
        boundary = sorted(candidates)[len(candidates) // 2]
    if boundary is None and target is not None:
        boundary = target

    rows = []
    for line in body:
        week = WEEK_START.match(line)
        if week:
            number = re.sub(r'\s+', '', week.group(1)).replace('&', '-')
            rest, at = line[week.end():], week.end()
        else:
            only = WEEK_ONLY.match(line)
            if only:
                rows.append({'week': only.group(1) + '-', 'topic': '', 'content': ''})
                continue
            if not rows or not re.search(r'\S', line):
                continue
            if rows[-1]['week'].endswith('-') and BARE.match(line) and not rows[-1]['topic']:
                rows[-1]['week'] += norm(line)
                continue
            rest, at = line, 0
        if boundary is None:
            topic, content = norm(rest), ''
        else:
            cut = max(0, boundary - at)
            # never cut a word in half: a column can sit a character or two either way in this PDF
            if 0 < cut < len(rest) and rest[cut - 1] != ' ' and rest[cut] != ' ':
                for delta in (1, -1, 2, -2, 3, -3):
                    if 0 <= cut + delta < len(rest) and (rest[cut + delta - 1] == ' ' or rest[cut + delta] == ' '):
                        cut += delta
                        break
            topic, content = norm(rest[:cut]), norm(rest[cut:])
        if week:
            rows.append({'week': number, 'topic': topic, 'content': content})
        else:
            if topic:
                rows[-1]['topic'] = norm(rows[-1]['topic'] + ' ' + topic)
            if content:
                rows[-1]['content'] = norm(rows[-1]['content'] + ' ' + content)
    return rows


def parse_region(lines, region):
    """A region's term tables, as {TERM: {theme, rows}}."""
    body = lines[region['start']:region['end']]
    terms, segments = OrderedDict(), []
    term_now, segment = None, None
    for line in body:
        if TERM_CLS.match(line) and TERM.match(line):
            region['cls'] = f"SS{TERM_CLS.match(line).group(1)}"
        heading = TERM.match(line)
        if heading:
            if segment:
                segments.append(segment)
            term_now = heading.group(1).upper()
            terms.setdefault(term_now, {'theme': '', 'rows': []})
            segment = None
            continue
        if term_now is None:
            continue
        theme = THEME.match(line)
        if theme and not terms[term_now]['rows']:
            terms[term_now]['theme'] = norm(theme.group(1))
            continue
        if HEADER.match(line):
            if segment:
                segments.append(segment)
            upper = line.upper()
            third = 'CONTENT' if 'CONTENT' in upper else 'BREAKDOWN'
            at = upper.find(third)
            segment = {'term': term_now, 'body': [], 'target': at if at > 0 else None}
            continue
        if segment is not None:
            if SUBJ.match(line) or is_title(line):
                segments.append(segment)
                segment = None
                continue
            if SKIP.match(line) or re.match(r'^\s*\(NEW NERDC', line):
                continue
            segment['body'].append(line)
    if segment:
        segments.append(segment)
    for seg in segments:
        terms[seg['term']]['rows'].extend(split_rows(seg['body'], seg['target']))
    for term in terms.values():
        for row in term['rows']:
            topic = row['topic']
            if re.search(r'\s[-\u2013]$', topic):
                row['topic'] = re.sub(r'\s[-\u2013]$', '', topic)
                row['content'] = re.sub(r'^\s+', '', row['content'])
            row['topic'] = re.sub(r'^[\s.,;:]+', '', row['topic']).strip()
            row['topic'] = re.sub(r'\s+', ' ', row['topic'])
            row['content'] = re.sub(r'\s+', ' ', row['content']).strip()
            row['week'] = row['week'].replace('\u2013', '-')
    return terms


def parse(text):
    """Every senior subject, class and term in the document's text."""
    lines = text.split('\n')
    _, headings = heading_index(lines)
    regions, seen = [], set()
    for idx, (line_no, class_here, subject) in enumerate(headings):
        key = (class_here, subject)
        if key in seen:
            continue
        seen.add(key)
        end = min([n for n, c, s in headings[idx + 1:] if (c, s) != key] + [len(lines)])
        regions.append({'cls': class_here, 'sub': subject, 'start': line_no, 'end': end})
    data = OrderedDict()
    for region in regions:
        terms = parse_region(lines, region)
        slot = data.setdefault((region['cls'], region['sub']), OrderedDict())
        for term, block in terms.items():
            if term in slot:
                slot[term]['rows'].extend(block['rows'])
            else:
                slot[term] = block
    return data


def kind_of(topic):
    lowered = topic.lower()
    for pattern, kind in NON_TEACHING:
        if re.search(pattern, lowered):
            return kind
    return 'teaching'


def for_school(parsed):
    """The requested subjects only, the document's class names mapped onto SSS 1-3."""
    data = OrderedDict()
    for subject in REQUESTED:
        data[subject] = OrderedDict()
        for cls in ('SS1', 'SS2', 'SS3'):
            terms = OrderedDict()
            for name in REQUESTED[subject].get(cls, []):
                block = parsed.get((cls, name))
                if not block:
                    continue
                for term in TERMS:
                    if term in block and block[term]['rows']:
                        terms[term] = {
                            'source': name,
                            'theme': block[term]['theme'],
                            'weeks': [{'week': r['week'], 'topic': r['topic'],
                                       'content': r['content'], 'kind': kind_of(r['topic'])}
                                      for r in block[term]['rows']],
                        }
            if terms:
                data[subject][cls] = terms
    return data


def write_markdown(data, cls, path):
    subjects = [(s, d[cls]) for s, d in data.items() if cls in d]
    out = [f"# {CLASS_TITLE[cls]} — scheme of work\n",
           f"NEW NERDC scheme, 2025 · {len(subjects)} subjects, one table per term. Weeks in *italics* "
           "are the term's own non-teaching weeks (midterm, break, revision, the exam), kept because "
           "they are part of the term's shape.\n"]
    total = sum(len(t['weeks']) for _, terms in subjects for t in terms.values())
    out[1] += f"\n**{total} weeks.**\n"
    for subject, terms in subjects:
        weeks = sum(len(t['weeks']) for t in terms.values())
        teaching = sum(1 for t in terms.values() for w in t['weeks'] if w['kind'] == 'teaching')
        out.append(f"## {subject}\n")
        out.append(f"{len(terms)} term{'s' if len(terms) != 1 else ''} · {weeks} weeks · "
                   f"{teaching} teaching weeks\n")
        for term in TERMS:
            if term not in terms:
                continue
            block = terms[term]
            out.append(f"### {TERM_TITLE[term]}\n")
            if block['theme']:
                out.append(f"**Theme:** {block['theme']}\n")
            out.append('| Week | Topic | Content |')
            out.append('|---|---|---|')
            for week in block['weeks']:
                topic = f"*{week['topic']}*" if week['kind'] != 'teaching' else week['topic']
                out.append(f"| {week['week']} | {topic} | {week['content'] or '—'} |")
            out.append('')
        out.append('')
    open(path, 'w').write('\n'.join(out))


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2])
        return 2
    text = subprocess.run(['pdftotext', '-layout', argv[1], '-'],
                          capture_output=True, text=True, check=True).stdout.replace('\f', '\n')
    here = os.path.dirname(os.path.abspath(__file__))
    data = for_school(parse(text))
    json.dump(data, open(os.path.join(here, 'schemes.json'), 'w'), indent=2, ensure_ascii=False)
    for cls in ('SS1', 'SS2', 'SS3'):
        write_markdown(data, cls, os.path.join(here, f"sss{cls[2]}.md"))
    weeks = sum(len(t['weeks']) for s in data.values() for c in s.values() for t in c.values())
    print(f"{len(data)} subjects, {weeks} weeks -> schemes.json, sss1.md, sss2.md, sss3.md")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
