"""Pass or fail a STIG scan against the organisation's accepted failures.

  gate.py receipt.json policy/accepted-failures.json [--fips] [--today YYYY-MM-DD]

A failed rule passes the gate only if an unexpired entry covers it by rule or by check, and the entry applies to this
kind of image (entries marked applies_to=non-fips do not cover an image scanned with --fips). Exit code 1 otherwise.
Standard library only.
"""
import datetime
import json
import sys


def main():
    args = sys.argv[1:]
    fips = "--fips" in args
    today = datetime.date.today()
    if "--today" in args:
        i = args.index("--today")
        today = datetime.date.fromisoformat(args[i + 1])
        del args[i:i + 2]
    if "--fips" in args:
        args.remove("--fips")
    if len(args) != 2 or any(a.startswith("-") for a in args):
        sys.exit(__doc__)  # an unknown option must not be ignored: a gate that skips its own flags passes too easily
    receipt_path, policy_path = args
    receipt = json.load(open(receipt_path))
    accepted = json.load(open(policy_path))["accepted"]

    problems = 0
    for entry in accepted:
        if datetime.date.fromisoformat(entry["expires"]) < today:
            print(f"EXPIRED  acceptance of {entry.get('check') or entry.get('rule')} expired {entry['expires']} "
                  f"(owner {entry['owner']}): review it or remove it")
            problems += 1

    for f in receipt["failed"]:
        cover = [e for e in accepted
                 if (e.get("rule") == f["rule"] or e.get("check") == f["check"])
                 and not (fips and e.get("applies_to") == "non-fips")
                 and datetime.date.fromisoformat(e["expires"]) >= today]
        if cover:
            print(f"ACCEPTED {f['severity']:7} {f['rule']:28} until {cover[0]['expires']} ({cover[0]['owner']})")
        else:
            print(f"FAIL     {f['severity']:7} {f['rule']:28} {f['title'][:80]}")
            problems += 1

    c = receipt["counts"]
    verdict = "PASS" if problems == 0 else "FAIL"
    print(f"{verdict}  {receipt['image']} {receipt['digest'][:19]}  pass {c.get('pass', 0)}  fail {c.get('fail', 0)}  "
          f"n/a {c.get('notapplicable', 0)}  unaccepted or expired {problems}")
    sys.exit(0 if problems == 0 else 1)


if __name__ == "__main__":
    main()
