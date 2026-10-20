#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Lays out each tests/dagre/NAME.graph with the dagre port and compares the
result with NAME.expected, which the original JavaScript dagre (dagre-d3-es
7.0.14) produced for the same graph. Numbers may differ in rounding only.

Usage: run-dagre.py DAGRE-DUMP DAGRE-DIR
"""

import pathlib
import re
import subprocess
import sys


def tokens(text):
    return [t for line in text.splitlines() for t in re.split(r"[ ,]", line.strip()) if t]


def same(a, b):
    if len(a) != len(b):
        return False
    for x, y in zip(a, b):
        try:
            if abs(float(x) - float(y)) > 0.0015:
                return False
        except ValueError:
            if x != y:
                return False
    return True


def main():
    dump, directory = sys.argv[1], pathlib.Path(sys.argv[2])
    graphs = sorted(directory.glob("*.graph"))
    failed = 0
    for graph in graphs:
        out = subprocess.run([dump, str(graph)], capture_output=True, text=True, check=True).stdout
        expected = graph.with_suffix(".expected").read_text()
        if not same(tokens(out), tokens(expected)):
            failed += 1
            print(f"FAIL {graph.name}")
    print(f"{len(graphs) - failed} of {len(graphs)} graphs match the original dagre")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
