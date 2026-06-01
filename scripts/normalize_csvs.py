import csv, os, re, sys
from pathlib import Path

SUBJECT_NORMALIZE = {
    "Agriculture": "Agricultural Science",
    "Cultural And Creative Arts": "Cultural and Creative Arts",
    "Physical And Health Education": "Physical and Health Education",
    "Yoruba": "Yoruba Language",
    "Yoruba Language": "Yoruba Language",
    "Information Technology": "Computer Studies",
    "Agricultural Science": "Agricultural Science",
}

TERM_NORMALIZE = {
    "1st Term": "Noel Term",
    "First Term": "Noel Term",
    "Noel Term": "Noel Term",
    "Calvary Term": "Calvary Term",
    "Second Term": "Calvary Term",
    "Summer Term": "Summer Term",
    "Third Term": "Summer Term",
}

HEADERS = ["class", "term", "week", "subject", "topic", "agegroup", "context", "generated"]

def normalize_row(row, generated):
    term = row.get("term", "").strip()
    subject = row.get("subject", "").strip()
    row["term"] = TERM_NORMALIZE.get(term, term)
    row["subject"] = SUBJECT_NORMALIZE.get(subject, subject)
    week_raw = str(row.get("week", "1")).strip()
    digits = re.sub(r"\D", "", week_raw)
    row["week"] = int(digits) if digits else 1
    for col in ["class", "topic", "agegroup"]:
        row[col] = row.get(col, "").strip()
    ctx = row.get("context", "")
    if not ctx or not str(ctx).strip():
        row["context"] = ""
    else:
        row["context"] = str(ctx).strip()
    row["generated"] = str(generated).lower()
    return row

def process_dir(input_dir, output_path, generated):
    rows = []
    for fpath in sorted(Path(input_dir).glob("*.csv")):
        print(f"  Reading {fpath.name}...", end=" ", flush=True)
        try:
            with open(fpath, newline="", encoding="utf-8") as f:
                try:
                    dialect = csv.Sniffer().sniff(f.read(4096))
                    f.seek(0)
                except:
                    dialect = "excel"
                reader = csv.DictReader(f, dialect=dialect)
                fieldnames = reader.fieldnames
                if fieldnames is None or None in fieldnames:
                    print(f"SKIP: header contains None fieldnames: {fieldnames}")
                    continue
                count = 0
                for raw in reader:
                    if None in raw:
                        print(f"WARN: row with None key (line {count+2}), skipping: {raw}")
                        continue
                    row = normalize_row(raw, generated)
                    rows.append(row)
                    count += 1
            print(f"{count} rows")
        except Exception as e:
            print(f"ERROR: {e}")
    rows.sort(key=lambda r: (r["class"], r["subject"], TERM_LIST.get(r["term"], 99), r["week"]))
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=HEADERS, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {output_path}")

TERM_LIST = {"Noel Term": 1, "Calvary Term": 2, "Summer Term": 3}
BASE = Path(__file__).resolve().parent.parent / "csv"
print("\nProcessing generated/...")
process_dir(BASE / "generated", BASE / "generated_topics.csv", generated=True)
print("\nProcessing ungenerated/...")
process_dir(BASE / "ungenerated", BASE / "ungenerated_topics.csv", generated=False)
print("\nDone.")
