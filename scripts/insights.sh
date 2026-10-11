#!/usr/bin/env bash
# What the Console's Insights tab will show, approximated locally for one directory tree: every container image the
# tree refers to, the Chainguard image that would replace it, and the CVE difference between the two.
#
# Insights (announced 8 October 2026, "available in the coming weeks") gets its inventory from Guardener scanning your
# GitHub repositories; this script uses scripts/inventory.py on a local checkout instead, grype for the counts, and the
# public cgr.dev/chainguard catalog, which serves :latest only. An organisation's catalog has version tags, so the
# Console can match versions; here python:3.12-slim is compared with Chainguard's latest python. Read the numbers as
# the shape of the result, not as what Insights will print for you.
#
#   scripts/insights.sh estate                     table on stdout, Dockerfile migrations by dfc after it
set -euo pipefail
dir=${1:?usage: insights.sh <dir>}
here=$(cd "$(dirname "$0")" && pwd)

cves() {  # "critical high total" for one image, scanned from the registry (no Docker needed)
  grype -q -o json "registry:$1" 2>/dev/null | jq -r '[.matches[].vulnerability.severity] as $s
    | "\($s | map(select(. == "Critical")) | length) \($s | map(select(. == "High")) | length) \($s | length)"'
}
equivalent() {  # cgr.dev/chainguard/<name>:latest when it exists, else nothing
  local name=${1%%[:@]*}; name=${name##*/}
  crane digest "cgr.dev/chainguard/$name:latest" >/dev/null 2>&1 && echo "cgr.dev/chainguard/$name:latest" || true
}

inv=$(python3 -I "$here/inventory.py" "$dir")
printf '%-38s %-5s %-34s %16s %16s\n' IMAGE REFS "CHAINGUARD EQUIVALENT" "CVES NOW (C/H/T)" "AFTER (C/H/T)"
tot_now=0; tot_after=0
while read -r img; do
  refs=$(grep -c "^$img	" <<<"$inv" || true)
  if [[ $img == cgr.dev/* ]]; then
    read -r c h t < <(cves "$img")
    printf '%-38s %-5s %-34s %16s %16s\n' "$img" "$refs" "(already Chainguard)" "$c/$h/$t" "-"
    continue
  fi
  eq=$(equivalent "$img")
  read -r c h t < <(cves "$img")
  if [ -n "$eq" ]; then
    read -r c2 h2 t2 < <(cves "$eq")
    tot_now=$((tot_now + t)); tot_after=$((tot_after + t2))
    printf '%-38s %-5s %-34s %16s %16s\n' "$img" "$refs" "$eq" "$c/$h/$t" "$c2/$h2/$t2"
  else
    printf '%-38s %-5s %-34s %16s %16s\n' "$img" "$refs" "(no public equivalent)" "$c/$h/$t" "?"
  fi
done < <(cut -f1 <<<"$inv" | sort -u)
echo
echo "where each image is referenced:"; sed 's/^/  /' <<<"$inv"
echo
echo "potential reduction for images with an equivalent: $tot_now -> $tot_after CVEs"
if command -v dfc >/dev/null; then
  echo
  echo "Dockerfile migrations (dfc; Guardener opens these as pull requests):"
  find "$dir" -name Dockerfile | sort | while read -r f; do
    d=$(dfc --org chainguard "$f" | diff -u --label "a/$f" --label "b/$f" "$f" - || true)
    [ -n "$d" ] && sed 's/^/  /' <<<"$d"
  done
fi
