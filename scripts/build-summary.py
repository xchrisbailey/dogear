#!/usr/bin/env python3
"""Summarises a timestamped xcodebuild log: where the wall-clock time went.

  scripts/app.sh test 2>&1 | scripts/build-summary.py stamp | tee build.log
  scripts/build-summary.py report build.log

`stamp` prefixes each line with the seconds since the first one. `report` prints the build
tasks run per target (a warm cache should leave the packages near zero) and the longest
silences in the log, which is where a slow simulator boot or a long compile shows up.
"""
import collections
import re
import sys
import time

STAMP = re.compile(r"^\[ *([0-9.]+)s\] (.*)$")
TASK = re.compile(r"^([A-Za-z]+) .*\(in target '([^']+)'")


def stamp():
    start = time.monotonic()
    for line in sys.stdin:
        sys.stdout.write(f"[{time.monotonic() - start:7.1f}s] {line}")
        sys.stdout.flush()


def report(path):
    rows = []
    with open(path, errors="replace") as log:
        for line in log:
            match = STAMP.match(line.rstrip("\n"))
            if match:
                rows.append((float(match.group(1)), match.group(2)))
    if not rows:
        print("build-summary: no timestamped lines")
        return

    tasks = collections.Counter()
    for _, text in rows:
        match = TASK.match(text)
        if match:
            tasks[match.groups()] += 1
    print("Build tasks run, by kind and target:")
    for (kind, target), count in tasks.most_common(40):
        print(f"  {count:4d}  {kind}  {target}")

    print("\nMilestones:")
    seen = set()
    for at, text in rows:
        for name, needle in (
            ("first build task", "(in target '"),
            ("first test starts", "◇ "),
            ("tests finished", "Test run with"),
            ("xcodebuild done", "** TEST "),
        ):
            if name not in seen and needle in text:
                seen.add(name)
                print(f"  {at:7.1f}s  {name}")
    print(f"  {rows[-1][0]:7.1f}s  last line")

    print("\nLongest silences (seconds, then the lines on either side):")
    gaps = sorted(
        ((b[0] - a[0], a, b) for a, b in zip(rows, rows[1:])), key=lambda g: -g[0]
    )[:12]
    for gap, before, after in sorted(gaps, key=lambda g: g[1][0]):
        print(f"  {gap:6.1f}s  from {before[0]:.1f}s")
        print(f"           after:  {before[1][:150]}")
        print(f"           before: {after[1][:150]}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "stamp":
        stamp()
    elif len(sys.argv) == 3 and sys.argv[1] == "report":
        report(sys.argv[2])
    else:
        sys.exit(f"usage: {sys.argv[0]} stamp | report <log>")
