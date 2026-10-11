#!/usr/bin/env bash
# Build each fixture in drift/ (a customisation teams commonly make to a base image), STIG-scan it, and show which
# rules changed result against the unmodified baseline. This is the question the Compliance tab cannot answer for you:
# Chainguard scans the images it ships; what you add on top is yours to scan.
#
#   scripts/drift.sh                 all fixtures
#   scripts/drift.sh http-mirror     one fixture (the baseline is scanned too if it has not been)
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH=$(docker version -f '{{.Server.Arch}}')
APKO=${APKO:-cgr.dev/chainguard/apko:latest}
fixtures=("$@"); [ ${#fixtures[@]} -gt 0 ] || fixtures=(corporate-ca-dockerfile corporate-ca-apko http-mirror ssh-server active-password)

build() {  # build one fixture as drift/<name>:local, from its Dockerfile or its apko.yaml
  local f=$1
  if [ -f "drift/$f/apko.yaml" ]; then
    docker run --rm -v "$PWD/drift/$f":/work -w /work "$APKO" build apko.yaml "drift/$f:local" /work/.image.tar \
      --arch "$ARCH" --sbom=false >/dev/null 2>&1 || { echo "apko build failed for $f" >&2; return 1; }
    docker load -q -i "drift/$f/.image.tar" >/dev/null && rm -f "drift/$f/.image.tar"
    docker tag "drift/$f:local-$ARCH" "drift/$f:local"
  else
    docker build -q -t "drift/$f:local" "drift/$f" >/dev/null
  fi
}

scan() { scripts/stig-scan.sh "drift/$1:local" "evidence/scans/$1" > "evidence/scans/$1.txt"; }

mkdir -p evidence/scans
[ -f evidence/scans/baseline/results.xml ] || { build baseline; scan baseline; }
printf '%-26s %6s %6s %6s   %s\n' FIXTURE PASS FAIL N/A "CHANGED AGAINST THE BASELINE"
b=$(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1]))["counts"]; print(c.get("pass",0),c.get("fail",0),c.get("notapplicable",0))' evidence/scans/baseline/receipt.json)
printf '%-26s %6s %6s %6s   %s\n' baseline $b "(Chainguard wolfi-base as shipped)"
for f in "${fixtures[@]}"; do
  build "$f"; scan "$f"
  c=$(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1]))["counts"]; print(c.get("pass",0),c.get("fail",0),c.get("notapplicable",0))' "evidence/scans/$f/receipt.json")
  printf '%-26s %6s %6s %6s\n' "$f" $c
  python3 -I scripts/stig-summary.py diff evidence/scans/baseline/results.xml "evidence/scans/$f/results.xml" \
    > "evidence/scans/$f.diff.txt"
  python3 -I scripts/stig-summary.py brief evidence/scans/baseline/results.xml "evidence/scans/$f/results.xml"
done
