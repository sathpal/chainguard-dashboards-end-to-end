"""Read an XCCDF results file the way the Compliance tab presents it.

  stig-summary.py text    results.xml                 counts by result type, then every failed rule
  stig-summary.py receipt results.xml key=value ...   receipt.json: the given facts plus counts and failed rules
  stig-summary.py rules   results.xml                 one line per rule: id, result, severity, title
  stig-summary.py diff    base.xml candidate.xml      every rule whose result differs from the base scan
  stig-summary.py brief   base.xml candidate.xml      the same, grouped by the check that drove the change

Standard library only, so it runs anywhere Python 3 does.
"""
import collections
import json
import sys
import xml.etree.ElementTree as ET

NS = {"x": "http://checklists.nist.gov/xccdf/1.2"}


def load(path):
    root = ET.parse(path).getroot()
    rules = {r.get("id"): r for r in root.iter("{%s}Rule" % NS["x"])}
    test = root.find(".//x:TestResult", NS)
    rows = []
    for rr in test.findall("x:rule-result", NS):
        rule = rules.get(rr.get("idref"))
        title = " ".join(rule.find("x:title", NS).text.split()) if rule is not None else ""
        check = rule.find(".//x:check/x:check-content-ref", NS) if rule is not None else None
        ident = rr.find("x:ident", NS)
        rows.append({
            "rule": rr.get("idref").removeprefix("xccdf_mil.disa.stig_rule_"),
            "result": rr.find("x:result", NS).text,
            "severity": rr.get("severity"),
            "cci": ident.text if ident is not None else "",
            "check": check.get("name") if check is not None else "",
            "title": title,
        })
    scores = {s.get("system").rsplit(":", 1)[-1]: float(s.text) for s in test.findall("x:score", NS)}
    return rows, scores


def counts(rows):
    c = collections.Counter(r["result"] for r in rows)
    return {k: c[k] for k in sorted(c)}


def main():
    mode, path, *kv = sys.argv[1:]
    rows, scores = load(path)
    failed = [r for r in rows if r["result"] in ("fail", "error", "unknown")]
    if mode == "text":
        c = counts(rows)
        print("result " + "  ".join(f"{k} {v}" for k, v in c.items()) + f"  (rules {len(rows)})")
        for r in failed:
            print(f"  {r['result'].upper():5} {r['severity'] or '':7} {r['rule']:28} {r['check']:30} {r['title'][:70]}")
        checks = collections.Counter(r["check"] for r in failed)
        if failed:
            print(f"  {len(failed)} failed rules come from {len(checks)} check(s): "
                  + ", ".join(f"{c} ({n})" for c, n in checks.items()))
    elif mode == "receipt":
        receipt = dict(a.split("=", 1) for a in kv)
        receipt.update({
            "profile": "xccdf_basic_profile_.check (Chainguard GPOS SRG)",
            "counts": counts(rows),
            "score": scores,
            "failed": [{k: r[k] for k in ("rule", "severity", "cci", "check", "title")} for r in failed],
        })
        json.dump(receipt, sys.stdout, indent=2)
        print()
    elif mode == "rules":
        for r in rows:
            print("\t".join((r["rule"], r["result"], r["severity"] or "", r["title"][:100])))
    elif mode in ("diff", "brief"):
        base = {r["rule"]: r for r in rows}
        cand_rows, _ = load(kv[0])
        changed = [(base.get(r["rule"], {}).get("result", "absent"), r) for r in cand_rows
                   if base.get(r["rule"], {}).get("result") != r["result"]]
        if mode == "diff":
            for before, r in changed:
                print(f"  {before:>13} -> {r['result']:13} {r['severity'] or '':7} {r['rule']:28} {r['title'][:70]}")
        else:
            groups = collections.defaultdict(list)
            for before, r in changed:
                groups[(before, r["result"], r["check"])].append(r)
            for (before, after, check), rs in groups.items():
                sev = collections.Counter(r["severity"] for r in rs)
                print(f"  {len(rs):3} {before} -> {after} via {check} ("
                      + ", ".join(f"{n} {k}" for k, n in sev.most_common()) + f"), e.g. {rs[0]['rule'].split('r')[0]}: "
                      + rs[0]["title"][:60])
        if not changed:
            print("  no rule changed result")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
