#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Lays out every test case and compares it with its expected scene.

Each tests/cases/**/NAME.mmd has a NAME.scene next to it: the output of
mermaid-dump, which lays out with fixed text sizes so that it is the same on
every machine. After an intended change, regenerate them with --update and
review the diff.

Usage: run-cases.py MERMAID-DUMP CASES-DIR [--update]
"""

import difflib
import pathlib
import subprocess
import sys


def main():
    dump, cases_dir = sys.argv[1], pathlib.Path(sys.argv[2])
    update = "--update" in sys.argv[3:]
    failed = 0
    cases = sorted(cases_dir.rglob("*.mmd"))
    for case in cases:
        out = subprocess.run([dump, str(case)], capture_output=True, text=True, check=True).stdout
        expected_file = case.with_suffix(".scene")
        if update:
            expected_file.write_text(out)
            continue
        expected = expected_file.read_text() if expected_file.exists() else ""
        if out != expected:
            failed += 1
            print(f"FAIL {case.relative_to(cases_dir)}")
            diff = difflib.unified_diff(expected.splitlines(), out.splitlines(),
                                        "expected", "actual", lineterm="", n=1)
            for i, line in enumerate(diff):
                if i >= 40:
                    print("   …")
                    break
                print("   " + line)
    if update:
        print(f"Updated {len(cases)} scenes")
        return 0
    print(f"{len(cases) - failed} of {len(cases)} cases match")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
