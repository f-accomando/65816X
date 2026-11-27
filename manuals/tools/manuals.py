#!/usr/bin/env python3
"""
manuals.py - build the manual and keep it up to date (manuals/README.md).

  manuals/tools/manuals.py build [--theme paper]   PDFs in manuals/pdf, then record what they come from
  manuals/tools/manuals.py build -o DIR            PDFs in DIR, without a record (preview, CI)
  manuals/tools/manuals.py check                   fails if the text or a source changed after the last build
  manuals/tools/manuals.py status                  one line for each manual

manuals/manuals.toml lists each manual and the repository files its text comes from. `build` stores a
hash of each of them in manuals/sync.json. `check` needs only Python; `build` also needs reportlab.

Adapted from core/scripts/manuals.py of f-accomando/bm (BM Community License 1.0), English only.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAN = os.path.join(ROOT, "manuals")
SYNC = os.path.join(MAN, "sync.json")
PDF = os.path.join(MAN, "pdf")
GAP = re.compile(r"\[TO FILL:")


def manuals():
    with open(os.path.join(MAN, "manuals.toml"), "rb") as f:
        return sorted(tomllib.load(f)["manual"], key=lambda m: m["order"])


def content_of(mid):
    return os.path.join(MAN, "content", "en", mid + ".md")


def digest(text):
    return hashlib.sha1(text.strip().replace("\r", "").encode("utf-8")).hexdigest()[:12]


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def file_hash(path):
    """hash of a file, or of all the files of a folder; "missing" if there is nothing"""
    if os.path.isdir(path):
        parts = []
        for d, dirs, files in sorted(os.walk(path)):
            dirs[:] = sorted(x for x in dirs if x != "__pycache__")
            parts += [name + digest(read(os.path.join(d, name))) for name in sorted(files)]
        return digest("".join(parts))
    if os.path.exists(path):
        return digest(read(path))
    return "missing"


def record_of(m):
    return {"content": file_hash(content_of(m["id"])),
            "sources": {s: file_hash(os.path.join(ROOT, s)) for s in m.get("sources", [])}}


def load_sync():
    return json.loads(read(SYNC)) if os.path.exists(SYNC) else {}


def problems(m, sync):
    mid = m["id"]
    now = record_of(m)
    bad = [f"source {s} does not exist" for s, v in now["sources"].items() if v == "missing"]
    if now["content"] == "missing":
        return bad + ["the content file does not exist"]
    old = sync.get(mid)
    if old is None:
        return bad + ["never built"]
    if not os.path.exists(os.path.join(PDF, mid + ".pdf")):
        bad.append("the PDF does not exist")
    if now["content"] != old["content"]:
        bad.append("the text changed after the last build")
    for s, v in now["sources"].items():
        if old["sources"].get(s) != v:
            bad.append(f"source {s} changed after the last build")
    return bad


def cmd_check(a):
    sync, rc = load_sync(), 0
    for m in manuals():
        bad = problems(m, sync)
        for b in bad:
            print(f"{m['id']}: {b}")
        if bad:
            rc = 1
            print(f"{m['id']}: read the changes, correct the text, then run: make manual")
        else:
            print(f"{m['id']}: up to date")
    return rc


def cmd_status(a):
    sync = load_sync()
    for m in manuals():
        p = content_of(m["id"])
        gaps = len(GAP.findall(read(p))) if os.path.exists(p) else "-"
        bad = problems(m, sync)
        print(f"{m['id']}: gaps {gaps}, {'up to date' if not bad else '; '.join(bad)}")
    return 0


def cmd_build(a):
    out = a.output or PDF
    sync = load_sync()
    for m in manuals():
        subprocess.run([sys.executable, os.path.join(HERE, "mkmanual.py"), content_of(m["id"]),
                        "--theme", a.theme, "-o", os.path.join(out, m["id"] + ".pdf")], check=True)
        sync[m["id"]] = record_of(m)
    if not a.output:
        with open(SYNC, "w", encoding="utf-8", newline="\n") as f:
            json.dump(sync, f, indent=1, sort_keys=True)
            f.write("\n")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").set_defaults(f=cmd_check)
    sub.add_parser("status").set_defaults(f=cmd_status)
    b = sub.add_parser("build")
    b.add_argument("--theme", default="paper")
    b.add_argument("-o", "--output")
    b.set_defaults(f=cmd_build)
    a = ap.parse_args()
    return a.f(a)


if __name__ == "__main__":
    sys.exit(main())
