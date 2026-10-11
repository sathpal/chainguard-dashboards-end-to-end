# Chainguard dashboards hands-on: every command, what it prints, what it proves

Chainguard's **Compliance Dashboard** became generally available on 7 October 2026. For each image it shows STIG
results, XCCDF reports to download, FIPS certificates, and signed validation receipts. The **Insights Dashboard** was
announced on 8 October and is due "in the coming weeks". This guide rebuilds what both dashboards show from public
images and open tools, then goes one step past them: to the images you build on top of Chainguard's.

All outputs below are from runs on 11 October 2026: Part A on a laptop (Docker Desktop, linux/arm64), Part B in GitHub
Actions (linux/amd64). Digests and timestamps will differ for you; rule results should not.

**You need:** Docker, `crane`, Python 3, `git`. For A7 also `grype`, `jq` and optionally `dfc`. No Chainguard account.

```bash
git clone https://github.com/sathpal/chainguard-dashboards-end-to-end && cd chainguard-dashboards-end-to-end
```

## Part A: on your laptop (about 20 minutes)

### A1. Scan a Chainguard image the way the Compliance tab reports it

```bash
scripts/stig-scan.sh cgr.dev/chainguard/wolfi-base:latest out/wolfi-base
```

```text
scan   cgr.dev/chainguard/wolfi-base:latest
       registry sha256:74e1bcf7505648076546f2fe4735d243163e366d8f2ccd46b224adfadd48b5e3 (linux/arm64)
with   cgr.dev/chainguard/openscap@sha256:4b5bcad6b4acfcb2e6d4fd25d5ce7aec83dcaa11affd5b468caaf95a04219783
result fail 5  notapplicable 107  pass 86  (rules 198)
  FAIL  high    SV-203739r987791_rule        oval:org.OpenSsl:def:1         The operating system must implement NSA-approved cryptography to prote
  FAIL  high    SV-203776r959006_rule        oval:org.OpenSsl:def:1         The operating system must implement NIST FIPS-validated cryptography f
  FAIL  medium  SV-203750r958912_rule        oval:org.OpenSsl:def:1         The operating system must maintain the confidentiality and integrity o
  FAIL  medium  SV-203751r958914_rule        oval:org.OpenSsl:def:1         The operating system must maintain the confidentiality and integrity o
  FAIL  medium  SV-203649r971535_rule        oval:org.OpenSsl:def:1         The operating system must use mechanisms meeting the requirements of a
  5 failed rules come from 1 check(s): oval:org.OpenSsl:def:1 (5)
wrote  out/wolfi-base/{results.xml,results.xml.sha256,report.html,receipt.json}
```

What happened, in order:

1. The tag was resolved to the digest of the manifest for your platform. Everything after this names that digest, so
   the result belongs to one artifact, not to a tag that will point somewhere else tomorrow.
2. The scanner is Chainguard's `openscap` image, which ships OpenSCAP and the Chainguard GPOS SRG profile (the one in
   [chainguard-dev/stigs](https://github.com/chainguard-dev/stigs)). It was also resolved to a digest and recorded.
3. `oscap-docker` mounted the image's filesystem and evaluated 198 rules. This needs the Docker socket and the host's
   pid namespace: it is a privileged scan. Run it on a build host, never on a production node.

Open `out/wolfi-base/report.html` in a browser for the same report OpenSCAP users know.

**Observation.** All five failures are the same check. `oval:org.OpenSsl:def:1` asserts that the OpenSSL FIPS
provider and its hardened configuration are installed and enabled. A non-FIPS image cannot pass it, by design; the
`-fips` variants exist for that. This is why the Compliance tab is built around an organisation's FIPS images.

### A2. Read the 107 "not applicable"

```bash
python3 scripts/stig-summary.py rules out/wolfi-base/results.xml | awk -F'\t' '$2=="notapplicable"' | cut -f1,4 \
  | grep -iE 'audit record|time|wireless' | head -5
```

```text
SV-259333r958940_rule  The operating system must install security-relevant software updates within the time period directed
SV-252688r958358_rule  The operating system must protect the confidentiality and integrity of communications with wireless
SV-203714r958788_rule  The operating system must record time stamps for audit records that can be mapped to Coordinated Uni
SV-203701r958754_rule  The operating system must offload audit records onto a different system or media from the system bei
SV-203700r958752_rule  The operating system must allocate audit record storage capacity to store at least one week's worth
```

DISA has never published a container SRG, so Chainguard applies the General Purpose OS SRG to containers and marks
the requirements that belong to the host or the runtime (audit, hardware, time, firewall, ASLR) as not applicable,
each with a rationale in the report. **When an assessor asks about them, the answer is your host's STIG**, not the
image's: a STIG-hardened node is where those controls live.

### A3. Check the XCCDF file the way its recipient would

The Compliance tab lets you download the XCCDF report and check its SHA-256. Each scan here writes both:

```bash
(cd out/wolfi-base && shasum -a 256 -c results.xml.sha256)
```

```text
results.xml: OK
```

And `receipt.json` ties the facts together: what was scanned (image, digest, platform), with what (scanner digest and
the profile's SHA-256), when, and the counts.

```bash
python3 -c 'import json; r=json.load(open("out/wolfi-base/receipt.json")); [print(f"{k:18} {r[k]}") for k in ("image","digest","platform","scanner","datastream_sha256","results_sha256","finished","counts")]'
```

A checksum proves the file was not damaged; it does not prove who produced it. Part B signs the receipt.

### A4. Scan what you build on top

The Compliance tab covers the images Chainguard ships. Most teams then add something. [`drift/`](../drift/) holds five
common additions, each a few lines on top of the same pinned `wolfi-base`:

```bash
scripts/drift.sh
```

```text
FIXTURE                      PASS   FAIL    N/A   CHANGED AGAINST THE BASELINE
baseline                       86      5    107   (Chainguard wolfi-base as shipped)
corporate-ca-dockerfile        85      6    107
    1 pass -> fail via oval:org.CABundleHash:def:1 (1 medium), e.g. SV-263659: The operating system must include only approved trust anchor
corporate-ca-apko              86      5    107
  no rule changed result
http-mirror                    85      6    107
    1 pass -> fail via oval:org.PackageSignature:def:1 (1 high), e.g. SV-203720: The operating system must prevent the installation of patche
ssh-server                     40     51    107
   46 pass -> fail via oval:org.RemoteAccessServices:def:1 (39 medium, 6 high, 1 low), e.g. SV-263652: The operating system must implement multifactor authenticati
active-password                55     36    107
   13 pass -> fail via oval:org.example:def:3 (11 medium, 2 high), e.g. SV-203629: The operating system must store only encrypted representatio
   18 pass -> fail via oval:org.NoUsers:def:1 (17 medium, 1 high), e.g. SV-263650: The operating system must disable accounts when the accounts
```

Full rule lists are in `evidence/scans/<fixture>.diff.txt`.

**Observations.**

- One `apk add dropbear` fails 46 rules. The check looks for remote-access packages, so it fails whether or not the
  daemon ever starts. Debug access belongs in an ephemeral debug container, not in the image.
- One `http://` line in `/etc/apk/repositories` is a high-severity failure: package downloads lose transport
  integrity. It turns up when an internal mirror is added during a proxy change.
- One unlocked `/etc/shadow` entry fails 31 rules. Chainguard images ship only locked accounts.

### A5. The corporate root CA, two ways

Banks and hospitals almost always add an internal root CA. Two fixtures add the same throwaway test certificate:

- [`corporate-ca-dockerfile`](../drift/corporate-ca-dockerfile/Dockerfile): copy it in, run `update-ca-certificates`.
- [`corporate-ca-apko`](../drift/corporate-ca-apko/apko.yaml): declare it under `certificates.additional` in the apko
  build definition.

```bash
for f in baseline corporate-ca-dockerfile corporate-ca-apko; do
  echo "## $f"
  docker run --rm --entrypoint sh drift/$f:local -c \
    'cd /etc/ssl/certs; cat .ca-certificates.crt.sha256; sha256sum ca-certificates.crt; grep -c "BEGIN CERT" ca-certificates.crt'
done
```

```text
## baseline
028fca5150ee1915c4474489985d55c54fceaa680c754cc8d1301734f01b2232  ca-certificates.crt
028fca5150ee1915c4474489985d55c54fceaa680c754cc8d1301734f01b2232  ca-certificates.crt
121
## corporate-ca-dockerfile
028fca5150ee1915c4474489985d55c54fceaa680c754cc8d1301734f01b2232  ca-certificates.crt
63742d36e0b5e846f682bfc6c0f902cfc3b2570be566b0776f7d1a4bc8e4d65b  ca-certificates.crt
122
## corporate-ca-apko
63742d36e0b5e846f682bfc6c0f902cfc3b2570be566b0776f7d1a4bc8e4d65b  ca-certificates.crt
63742d36e0b5e846f682bfc6c0f902cfc3b2570be566b0776f7d1a4bc8e4d65b  ca-certificates.crt
122
```

The first line of each block is the SHA-256 apko recorded when it built the image (the "sidecar"); the second is the
bundle as it is now. Both CA images trust the same 122 roots, byte for byte. In the apko image the record matches;
in the Dockerfile image it still describes the bundle before the CA was added. The trust-anchor rule (SV-263659,
CCI-004909, "only approved trust anchors") compares the two, so one passes and one fails.

**The point to take into a design review:** "approved" means declared in a reviewed build definition, and the
sidecar is the evidence. A certificate added in a later layer may be perfectly legitimate, but the image can no longer
prove it. Chainguard's own explanation is in
[certificate-audit.md](https://github.com/chainguard-dev/stigs/blob/main/docs/certificate-audit.md). For images in
your organisation's Chainguard catalog, Custom Assembly is the managed way to declare additions; the Compliance
Dashboard announcement lists Custom Assembly support as a fast follow.

### A6. Gate on the result, with acceptances that expire

A scan that only reports is ignored. [`scripts/gate.py`](../scripts/gate.py) fails on any failed rule that is not
covered by an entry in [`policy/accepted-failures.json`](../policy/accepted-failures.json). Each entry has a reason,
an owner and an expiry date, and an entry marked `non-fips` does not cover a FIPS image.

```bash
python3 scripts/gate.py out/wolfi-base/receipt.json policy/accepted-failures.json
python3 scripts/gate.py evidence/scans/corporate-ca-dockerfile/receipt.json policy/accepted-failures.json
python3 scripts/gate.py out/wolfi-base/receipt.json policy/accepted-failures.json --today 2027-02-01
python3 scripts/gate.py out/wolfi-base/receipt.json policy/accepted-failures.json --fips
```

```text
ACCEPTED high    SV-203739r987791_rule        until 2027-01-31 (platform-security)
...
PASS  cgr.dev/chainguard/wolfi-base:latest sha256:74e1bcf75056  pass 86  fail 5  n/a 107  unaccepted or expired 0

FAIL     medium  SV-263659r982563_rule        The operating system must include only approved trust anchors in trust stores or
FAIL  drift/corporate-ca-dockerfile:local sha256:21044851f10d  pass 85  fail 6  n/a 107  unaccepted or expired 1

EXPIRED  acceptance of oval:org.OpenSsl:def:1 expired 2027-01-31 (owner platform-security): review it or remove it
...
FAIL  cgr.dev/chainguard/wolfi-base:latest sha256:74e1bcf75056  pass 86  fail 5  n/a 107  unaccepted or expired 6

...
FAIL  cgr.dev/chainguard/wolfi-base:latest sha256:74e1bcf75056  pass 86  fail 5  n/a 107  unaccepted or expired 5
```

**Observation.** The expiry is what keeps an acceptance honest: on 1 February 2027 the same image fails until someone
re-approves or removes the entry. That is a risk register entry with a review date, enforced by CI.

### A7. Insights, approximated

The Insights tab will inventory every image your GitHub repositories reference and show the Chainguard equivalent and
the CVE difference. [`estate/`](../estate/) is a small sample: a Python service, a Go service already on Chainguard, a
Helm chart for nginx and a Postgres StatefulSet.

```bash
scripts/insights.sh estate
```

```text
IMAGE                                  REFS  CHAINGUARD EQUIVALENT              CVES NOW (C/H/T)    AFTER (C/H/T)
cgr.dev/chainguard/go:latest           1     (already Chainguard)                          0/0/0                -
cgr.dev/chainguard/static:latest       1     (already Chainguard)                          0/0/0                -
nginx:1.27                             1     cgr.dev/chainguard/nginx:latest          38/235/672            0/0/0
postgres:16                            1     cgr.dev/chainguard/postgres:latest         3/88/309            0/0/0
python:3.12-slim                       1     cgr.dev/chainguard/python:latest           0/55/172            0/0/2

where each image is referenced:
  postgres:16	k8s/postgres.yaml:15
  nginx:1.27	charts/web/values.yaml:3
  python:3.12-slim	services/payments/Dockerfile:1
  cgr.dev/chainguard/go:latest	services/ledger/Dockerfile:1
  cgr.dev/chainguard/static:latest	services/ledger/Dockerfile:6

potential reduction for images with an equivalent: 1153 -> 2 CVEs

Dockerfile migrations (dfc; Guardener opens these as pull requests):
  ...
  --- a/estate/services/payments/Dockerfile
  +++ b/estate/services/payments/Dockerfile
  @@ -1,4 +1,4 @@
  -FROM python:3.12-slim
  +FROM cgr.dev/chainguard/python:3.12-dev
```

**Be fair with these numbers.** The estate pins tags teams commonly leave in place. At today's upstream tags the
three images carry 774, not 1,153 ([`insights-current-tags.txt`](../evidence/insights-current-tags.txt): nginx:stable
1.30.5 has 304, postgres 18.6 has 309, python:slim has 161). And the public catalog serves `:latest` only, so this
compares Python 3.12 with Chainguard's latest Python; an organisation's catalog, which Insights uses, matches versions.
The migration dfc proposes (`python:3.12-dev`) needs that catalog too.

### A8. The FIPS panel: what it takes

The FIPS certificate panel needs `-fips` images, which need a FIPS entitlement, so this repository does not run it.
With access, Chainguard documents these checks ([Verifying FIPS configuration](https://edu.chainguard.dev/platform/fips/verify-fips/)):

```bash
docker run --rm --entrypoint openssl-fips-test cgr.dev/$ORGANIZATION/python-fips   # module, self-tests, CMVP and ESV certificate
scripts/stig-scan.sh cgr.dev/$ORGANIZATION/python-fips:latest out/python-fips        # the five OpenSsl rules should pass
python3 scripts/gate.py out/python-fips/receipt.json policy/accepted-failures.json --fips
```

The image SBOMs also mark validated components with `NIST-CMVP-<n>` and `NIST-ESV-<n>` package prefixes, which is
where certificate numbers come from when an auditor asks for them.

## Part B: on GitHub

### B1. Fork and run

Fork the repository, enable Actions, and run **compliance** from the Actions tab (it also runs on push, on pull
requests and every Monday). Five jobs:

| Job | What it does |
|---|---|
| `scan <image>` (3) | A1 and A6 for `wolfi-base`, `python` and `nginx`, with a dashboard table in the job summary |
| `drift` | A4 on linux/amd64 |
| `signed receipt` | Builds the apko CA image, pushes it to GHCR, scans it by digest, gates it, and attests the receipt |

Every action is a [Chainguard Actions](https://github.com/sathpal/chainguard-actions-end-to-end) copy pinned by SHA,
and Dependabot keeps both the pins and the fixtures' base-image digests current.

On linux/amd64 every drift fixture matched the laptop's arm64 scan rule for rule, and the three registry images gave
the same counts ([`ci-runs.txt`](../evidence/ci-runs.txt)).

### B2. Verify the receipt as a consumer would

The receipt job ends with `cosign attest`: the receipt becomes a signed in-toto statement whose subject is the image
digest, signed keyless with the workflow's own identity. Anyone with pull access can check it:

```bash
cosign verify-attestation \
  --type https://github.com/<you>/chainguard-dashboards-end-to-end/stig-receipt/v1 \
  --certificate-identity https://github.com/<you>/chainguard-dashboards-end-to-end/.github/workflows/compliance.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/<you>/chainguard-dashboards-end-to-end/corp-base@sha256:<digest from the job log> \
  | jq -r '.payload | @base64d | fromjson | .predicate | "\(.digest) \(.platform) \(.counts)"'
```

```text
sha256:36941fa0d16b432b4e5b97fc78bd80c1d41f833ec3fed72a151e63f92d7ed7e2 linux/amd64 {"fail":5,"notapplicable":107,"pass":86}
sha256:36941fa0d16b432b4e5b97fc78bd80c1d41f833ec3fed72a151e63f92d7ed7e2 linux/amd64 {"fail":5,"notapplicable":107,"pass":86}
```

Change the identity to any other workflow and it is refused:

```text
failed to verify certificate identity: no matching CertificateIdentity found, last error: expected SAN value
"https://github.com/.../.github/workflows/other.yml@refs/heads/main", got "https://github.com/.../.github/workflows/compliance.yml@refs/heads/main"
```

**Observation.** Two receipts, one digest. apko builds are reproducible, so the second run rebuilt the identical image
and attested a second scan to it. Receipts accumulate as a scan history on the artifact itself, the same idea as the
historical reports in the Compliance tab.

GHCR creates the package as private. To let others verify without credentials, make it public in the package
settings.

## Failures we hit, and the fixes

| What happened | Why | Fix |
|---|---|---|
| apko: `x509: invalid ECDSA parameters` | macOS LibreSSL's `req -newkey ec` wrote the curve as explicit parameters; Go only accepts named curves | `openssl ecparam -name prime256v1 -genkey`, then `req -new -x509 -key` |
| Local builds were looked up on Docker Hub | Docker's containerd image store gives local builds a `RepoDigests` entry too | Ask the registry first; fall back to the local image ID |
| `drift/baseline:local` built as `drift/baselineocal` | zsh read `$f:l` as the lowercase modifier | Write `${f}:local` |
| `apko build` loaded `:local-arm64`, not `:local` | apko suffixes the architecture to the tag | `docker tag` after loading |
| CI drift step failed on a missing directory, and the pipe hid it | The step removed `evidence/scans`; Actions' bash has no `pipefail` | `mkdir -p` in the script, `set -o pipefail` in the step |

## Caveats

- **This is not the Console.** The receipts here are signed by this repository's workflow, not by Chainguard.
- **The scanner is privileged.** It needs the Docker socket and the host pid namespace.
- **`openscap:latest-dev` is resolved at run time**, on purpose, so a scheduled scan uses the newest profile. The
  digest is recorded in every receipt, so a result can always be traced to the exact profile.
- **The CA fixtures use a throwaway certificate** whose private key was discarded when it was created.
- **Not applicable is not compliant.** 107 rules are for the host and runtime to meet.

## Good to know

- `xccdf_basic_profile_.check` is the profile ID in Chainguard's datastream.
- `oscap-docker image <name>` scans an image without running it; `oscap-docker container <name>` scans a running one.
- Chainguard's [stigs repository](https://github.com/chainguard-dev/stigs) has an end-to-end test fixture per rule;
  three of the drift fixtures here follow its patterns.
- Chainguard also maintains [chainguard-inspec](https://github.com/chainguard-dev/chainguard-inspec) for teams on
  InSpec.
