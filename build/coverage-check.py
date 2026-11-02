#!/usr/bin/env python3
"""Summarize Cobertura coverage and enforce a minimum line coverage (stdlib only)."""
import argparse
import glob
import re
import sys
import xml.etree.ElementTree as ET

COND = re.compile(r"\((\d+)/(\d+)\)")


def rel(path):
    p = path.replace("\\", "/")
    i = p.rfind("/src/")
    if i >= 0:
        return p[i + 1:]
    if p.startswith("src/"):
        return p
    return path


def fail(msg):
    print(msg, file=sys.stderr)
    return 2


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("files", nargs="+", help="Cobertura files or glob patterns")
    ap.add_argument("--min", type=float, default=80.0, dest="minimum")
    ap.add_argument("--packages", default="CronScheduler.Extensions,CronScheduler.AspNetCore")
    ap.add_argument("--summary", default=None)
    args = ap.parse_args()

    matched = []
    for pat in args.files:
        for f in sorted(glob.glob(pat, recursive=True)):
            if f not in matched:
                matched.append(f)
    if not matched:
        return fail("error: no coverage file matches " + " ".join(args.files))

    wanted = [x.strip() for x in args.packages.split(",") if x.strip()]
    present = []
    lines = {}   # (file, number) -> covered bool
    branch = {}  # (file, number) -> (covered, total)
    for f in matched:
        try:
            root = ET.parse(f).getroot()
            if root.tag != "coverage":
                raise ValueError("root element is not <coverage>")
        except (ET.ParseError, ValueError, OSError) as e:
            return fail("error: %s is not a parseable Cobertura file: %s" % (f, e))
        for pkg in root.iter("package"):
            name = pkg.get("name")
            if name not in wanted:
                continue
            if name not in present:
                present.append(name)
            for cls in pkg.iter("class"):
                fn = rel(cls.get("filename", ""))
                for ln in cls.iter("line"):
                    key = (fn, int(ln.get("number")))
                    hit = int(ln.get("hits", "0")) > 0
                    lines[key] = lines.get(key, False) or hit
                    if ln.get("branch") == "True":
                        m = COND.search(ln.get("condition-coverage", ""))
                        if m:
                            c, t = int(m.group(1)), int(m.group(2))
                            if key not in branch or c > branch[key][0]:
                                branch[key] = (c, t)
    if not present:
        return fail("error: none of the packages %s is present in the report" % ", ".join(wanted))
    if not lines:
        return fail("error: the included packages hold zero lines")

    per = {}
    for (fn, _), cov in lines.items():
        v = per.setdefault(fn, [0, 0])
        v[1] += 1
        v[0] += 1 if cov else 0
    total_c = sum(v[0] for v in per.values())
    total_v = sum(v[1] for v in per.values())
    pct = 100.0 * total_c / total_v
    bt = sum(t for _, t in branch.values())
    bpct = (100.0 * sum(c for c, _ in branch.values()) / bt) if bt else None

    print("PACKAGES " + ", ".join(present))
    rows = []
    for fn in sorted(per):
        c, v = per[fn]
        p = 100.0 * c / v
        print("FILE %s %d/%d %.2f%%" % (fn, c, v, p))
        rows.append((fn, v, c, p))
    bstr = "%.2f%%" % bpct if bpct is not None else "n/a"
    print("LINE_COVERAGE=%.2f%%" % pct)
    print("BRANCH_COVERAGE=" + bstr)
    ok = pct >= args.minimum
    print("RESULT=PASS" if ok else "RESULT=FAIL (min %s%%)" % ("%g" % args.minimum))

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write("## Code coverage\n\n| File | Lines | Covered | Line % |\n|---|---:|---:|---:|\n")
            for fn, v, c, p in rows:
                fh.write("| %s | %d | %d | %.2f%% |\n" % (fn, v, c, p))
            fh.write("\n**Total:** line %.2f%% (%d/%d), branch %s (minimum line %g%%)\n\n"
                     % (pct, total_c, total_v, bstr, args.minimum))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
