#!/usr/bin/env bash
# STIG-scan one image and write the evidence the Console's Compliance tab shows for it:
#   results.xml          XCCDF results (the file the Compliance tab lets you download)
#   results.xml.sha256   its checksum, so whoever receives the file can check it
#   report.html          the human-readable OpenSCAP report
#   receipt.json         what was scanned (image, digest, platform), with what (scanner digest, datastream digest),
#                        when, and the result counts: the facts a "validation receipt" has to tie together
#
# The scanner is Chainguard's openscap image, which ships the Chainguard GPOS SRG profile
# (github.com/chainguard-dev/stigs). Everything runs locally against your Docker daemon; no Chainguard account needed.
#
#   scripts/stig-scan.sh cgr.dev/chainguard/wolfi-base:latest            # a registry image, scanned by digest
#   scripts/stig-scan.sh drift/http-mirror:local evidence/scans/http     # a local build that was never pushed
#
# Exit code: 0 when the scan ran, whatever it found (gating is scripts/gate.py's job); 1 when it could not run.
set -euo pipefail

img=${1:?usage: stig-scan.sh <image> [outdir]}
out=${2:-out/$(printf '%s' "${img%%@*}" | tr '/:' '__')}
SCANNER=${SCANNER:-cgr.dev/chainguard/openscap:latest-dev}
PLATFORM=${PLATFORM:-linux/$(docker version -f '{{.Server.Arch}}')}
DS=/usr/share/xml/scap/ssg/content/ssg-chainguard-gpos-ds.xml
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"; out=$(cd "$out" && pwd)

# What exactly is being scanned. A registry image is pinned to the digest of the manifest for this platform, so the
# receipt names one artifact, not a tag that will move tomorrow. A local build that was never pushed has no registry
# digest; its local image ID is recorded instead and the receipt says source=local.
if digest=$(crane digest --platform "$PLATFORM" "$img" 2>/dev/null); then
  source=registry
  repo=${img%%@*}; [[ ${repo##*/} == *:* ]] && repo=${repo%:*}
  target="$repo@$digest"
  docker pull -q --platform "$PLATFORM" "$target" >/dev/null
elif docker image inspect "$img" >/dev/null 2>&1; then
  source=local; digest=$(docker image inspect -f '{{.Id}}' "$img"); target=$img
else
  echo "cannot resolve $img in a registry or in the local Docker daemon" >&2; exit 1
fi
scanner_digest=$(crane digest --platform "$PLATFORM" "$SCANNER")
scanner_ref="${SCANNER%:*}@$scanner_digest"
docker pull -q --platform "$PLATFORM" "$scanner_ref" >/dev/null

echo "scan   $img"
echo "       $source $digest ($PLATFORM)"
echo "with   $scanner_ref"

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# oscap-docker mounts the target image's filesystem and evaluates the profile against it; it needs the host's Docker
# socket and pid namespace, so this is a privileged scan. Run it on a build host, never on a production node.
docker run -i --rm -u 0:0 --pid=host --platform "$PLATFORM" \
  -v /var/run/docker.sock:/var/run/docker.sock -v "$out":/out \
  --entrypoint sh "$scanner_ref" >"$out/oscap.log" 2>&1 <<EOF || true
oscap --version | head -1 > /out/oscap-version.txt
sha256sum $DS | cut -d' ' -f1 > /out/datastream.sha256
oscap-docker image "$target" xccdf eval --profile xccdf_basic_profile_.check \
  --report /out/report.html --results /out/results.xml $DS
EOF
finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -s "$out/results.xml" ] || { echo "scan failed; see $out/oscap.log" >&2; tail -5 "$out/oscap.log" >&2; exit 1; }

(cd "$out" && shasum -a 256 results.xml > results.xml.sha256)
python3 -I "$here/stig-summary.py" receipt "$out/results.xml" \
  image="$img" source="$source" digest="$digest" platform="$PLATFORM" scanner="$scanner_ref" \
  scanner_version="$(cat "$out/oscap-version.txt")" datastream_sha256="$(cat "$out/datastream.sha256")" \
  results_sha256="$(cut -d' ' -f1 "$out/results.xml.sha256")" started="$started" finished="$finished" \
  > "$out/receipt.json"
rm -f "$out/oscap-version.txt" "$out/datastream.sha256"
python3 -I "$here/stig-summary.py" text "$out/results.xml"
echo "wrote  $out/{results.xml,results.xml.sha256,report.html,receipt.json}"
