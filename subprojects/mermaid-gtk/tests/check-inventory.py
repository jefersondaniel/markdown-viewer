#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Checks that FEATURES.md and the test cases agree.

Every feature marked supported or partial needs a test case that lists its
id on a "%% features:" line, and every id in a test case must be in the table
with one of those statuses. A "%% ignored:" line lists features that aren't
supported but must not break the diagram; they only need to be in the table.

Usage: check-inventory.py FEATURES.md CASES-DIR
"""

import pathlib
import re
import sys

ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|.*\|\s*(✅|🟡|❌|⛔)[^|]*\|")
TESTED = {"✅", "🟡"}


def main():
    features_md, cases_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    status = {}
    errors = []
    for n, line in enumerate(features_md.read_text().splitlines(), 1):
        m = ROW.match(line)
        if m:
            fid, mark = m.groups()
            if fid in status:
                errors.append(f"{features_md.name}:{n}: {fid} is listed twice")
            status[fid] = mark

    covered = {}
    for case in sorted(cases_dir.rglob("*.mmd")):
        ids = []
        ignored = []
        for line in case.read_text().splitlines():
            if line.strip().startswith("%% features:"):
                ids += line.split(":", 1)[1].split()
            elif line.strip().startswith("%% ignored:"):
                ignored += line.split(":", 1)[1].split()
        if not ids and not ignored:
            errors.append(f"{case}: no “%% features:” line")
        for fid in ignored:
            if fid not in status:
                errors.append(f"{case}: {fid} isn't in {features_md.name}")
        for fid in ids:
            if fid not in status:
                errors.append(f"{case}: {fid} isn't in {features_md.name}")
            elif status[fid] not in TESTED:
                errors.append(f"{case}: {fid} is tested but marked {status[fid]} in {features_md.name}")
            covered.setdefault(fid, case)

    # Diagram types are covered by the cases of their diagrams.
    for fid, mark in status.items():
        if mark in TESTED and fid not in covered and not fid.startswith("type."):
            errors.append(f"{features_md.name}: {fid} is {mark} but no test case covers it")

    for e in errors:
        print(e)
    supported = sum(1 for m in status.values() if m == "✅")
    partial = sum(1 for m in status.values() if m == "🟡")
    print(f"{len(status)} features: {supported} supported, {partial} partial, "
          f"{len(status) - supported - partial} not supported")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
