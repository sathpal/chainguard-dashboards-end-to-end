"""Render STIG receipts as a Markdown table: the overview the Compliance tab gives per image, for many images at once.

  dashboard.py receipt.json [receipt.json ...] > dashboard.md

Standard library only.
"""
import json
import sys

print("| Image | Digest | Platform | Pass | Fail | N/A | Failed checks | Scanned |")
print("|---|---|---|---:|---:|---:|---|---|")
for path in sys.argv[1:]:
    r = json.load(open(path))
    c = r["counts"]
    checks = sorted({f["check"].removeprefix("oval:org.").removesuffix(":def:1") for f in r["failed"]})
    print(f"| `{r['image']}` | `{r['digest'][:19]}` | {r['platform']} | {c.get('pass', 0)} | {c.get('fail', 0)} | "
          f"{c.get('notapplicable', 0)} | {', '.join(checks) or '-'} | {r['finished']} |")
