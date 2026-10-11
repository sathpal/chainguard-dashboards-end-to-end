---
title: "Chainguard's Compliance Dashboard is GA. I rebuilt it from the command line, then scanned the part it can't see"
published: false
description: "STIG results, XCCDF reports and signed receipts for Chainguard images, reproduced with open tools, plus what happens to the scan when you add a corporate CA, a mirror or an SSH server on top."
tags: security, devops, docker, compliance
---

Here are two container images built on the same Chainguard base. Both trust exactly the same 122 root certificates, and their CA bundles are byte-for-byte identical. One passes the STIG rule "the operating system must include only approved trust anchors". The other fails it.

The only difference is *how* the corporate root CA got in. That difference is invisible on any dashboard that only covers the images a vendor ships, and it is exactly the question an assessor asks about the image you actually run.

On 7 October 2026 Chainguard made its [Compliance Dashboard](https://www.chainguard.dev/unchained/announcing-the-chainguard-compliance-dashboard) generally available. A day later it announced an [Insights Dashboard](https://www.chainguard.dev/unchained/introducing-the-chainguard-console-insights-dashboard-powered-by-guardener). I spent a day rebuilding what both show, from public images and open tools, and then pointed the same checks at the images teams build *on top of* Chainguard's. Everything below came from runs you can open and repeat:

{% github sathpal/chainguard-dashboards-end-to-end %}

## TL;DR

- **The Compliance Dashboard is GA; Insights is not yet.** Compliance is "available today for all Chainguard Console users". Insights is due "in the coming weeks", and Guardener, which feeds it, is in Early Access.
- **Chainguard images as shipped:** 86 rules pass, 107 don't apply to a container, 5 fail. All 5 failures are one check, FIPS-validated cryptography, which only a `-fips` image can pass. Same result on `wolfi-base`, `python` and `nginx`, on arm64 and amd64.
- **What you add on top is where compliance breaks.** An SSH server fails 46 rules. A plain-http package mirror fails a high-severity rule. A corporate CA added with `update-ca-certificates` fails the trust-anchor rule; the same CA declared in the apko build definition passes.
- **A receipt is only useful signed.** CI scans the image by digest, gates the result, and attests the receipt to the digest with cosign. It verifies for that workflow and is refused for any other.
- **Insights, approximated:** three upstream images in a sample estate carry 1,153 CVEs at the tags the estate pins, 774 at today's tags. Their public Chainguard equivalents carry 2.

## What the Compliance Dashboard shows

For each image in your organisation's catalog, the Console's Compliance tab shows:

- DISA STIG results against the General Purpose Operating System SRG, rule by rule.
- The XCCDF report, to download and check against its SHA-256.
- FIPS 140-3 module and entropy-source certificate numbers.
- Signed validation receipts tied to the exact tag, architecture and digest that was evaluated.

It updates with every image build, and the announcement lists Custom Assembly support as a fast follow. All of that is evidence an assessor can use, produced by Chainguard for the images Chainguard builds.

Nothing in this post logs in to the Console. Instead I asked: can I produce each of those pieces myself, for any image, in CI? It turns out you can, with Chainguard's own scanner image.

## Step 1: Scan a Chainguard image the way the Compliance tab does

Chainguard publishes its STIG profile in [chainguard-dev/stigs](https://github.com/chainguard-dev/stigs) and ships it inside a public `openscap` image. A short script pins the target to a digest, runs `oscap-docker` against it, and writes the report, the XCCDF results, a checksum and a receipt:

```bash
scripts/stig-scan.sh cgr.dev/chainguard/wolfi-base:latest out/wolfi-base
```

```text
scan   cgr.dev/chainguard/wolfi-base:latest
       registry sha256:74e1bcf7505648076546f2fe4735d243163e366d8f2ccd46b224adfadd48b5e3 (linux/arm64)
with   cgr.dev/chainguard/openscap@sha256:4b5bcad6b4acfcb2e6d4fd25d5ce7aec83dcaa11affd5b468caaf95a04219783
result fail 5  notapplicable 107  pass 86  (rules 198)
  FAIL  high    SV-203739r987791_rule   oval:org.OpenSsl:def:1   The operating system must implement NSA-approved cryptography ...
  FAIL  high    SV-203776r959006_rule   oval:org.OpenSsl:def:1   The operating system must implement NIST FIPS-validated cryptography ...
  FAIL  medium  SV-203750r958912_rule   oval:org.OpenSsl:def:1   ...
  FAIL  medium  SV-203751r958914_rule   oval:org.OpenSsl:def:1   ...
  FAIL  medium  SV-203649r971535_rule   oval:org.OpenSsl:def:1   ...
  5 failed rules come from 1 check(s): oval:org.OpenSsl:def:1 (5)
```

Ten seconds, and three things to read in it.

**The five failures are one check.** `oval:org.OpenSsl:def:1` asserts that the OpenSSL FIPS provider and its hardened configuration are installed and enabled. A non-FIPS image can't pass it, by design. That is why the Compliance tab is built around an organisation's FIPS images, and why the FIPS panel needs a FIPS entitlement I don't have.

**107 rules are "not applicable".** DISA has never published a container SRG, so Chainguard applies the OS-level one and marks the requirements that belong to the host or runtime, such as audit offloading, time sync, wireless and firewall. When an assessor asks about those, the answer is your node's STIG, not the image's.

**Everything is pinned.** The tag became a digest before the scan, and the scanner ran by digest too. Both go into `receipt.json` with the profile's SHA-256, the results file's SHA-256, the timestamps and the counts. A result that names a tag describes something that will be different tomorrow.

## Step 2: Scan what you build on top

This is the part no vendor dashboard can cover: almost nobody runs a base image unmodified. I wrote five fixtures, each a few lines on top of the same pinned `wolfi-base`, modelled on common customisations (three follow test fixtures in Chainguard's own STIG repository), and diffed each scan against the unmodified image:

```text
FIXTURE                      PASS   FAIL    N/A   CHANGED AGAINST THE BASELINE
baseline                       86      5    107   (Chainguard wolfi-base as shipped)
corporate-ca-dockerfile        85      6    107
    1 pass -> fail via oval:org.CABundleHash:def:1 (1 medium), e.g. SV-263659: ...only approved trust anchors
corporate-ca-apko              86      5    107
  no rule changed result
http-mirror                    85      6    107
    1 pass -> fail via oval:org.PackageSignature:def:1 (1 high), e.g. SV-203720: ...installation of patches
ssh-server                     40     51    107
   46 pass -> fail via oval:org.RemoteAccessServices:def:1 (39 medium, 6 high, 1 low)
active-password                55     36    107
   13 pass -> fail via oval:org.example:def:3 (11 medium, 2 high)
   18 pass -> fail via oval:org.NoUsers:def:1 (17 medium, 1 high)
```

- **`apk add dropbear` "for debugging" fails 46 rules.** The check looks for remote-access packages, so the daemon doesn't have to run. Debug access belongs in an ephemeral debug container.
- **One `http://` line in `/etc/apk/repositories` is a high-severity failure.** Package downloads lose transport integrity. It can creep in when an internal mirror is added during a proxy change.
- **One unlocked `/etc/shadow` entry fails 31 rules.** Chainguard images ship locked accounts only.

## Step 3: The same CA, two verdicts

Regulated organisations routinely add an internal root CA. Two fixtures add the same throwaway test certificate. One copies it in and runs `update-ca-certificates` in a Dockerfile layer. The other declares it in the apko build definition:

```yaml
certificates:
  additional:
    - name: example-corp-root
      content: |
        -----BEGIN CERTIFICATE-----
        ...
```

Then look inside each image. The first line is the SHA-256 that apko recorded beside the bundle when it built the image; the second is the bundle as it is now:

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

Both CA images trust the same 122 roots, byte for byte. In the apko image the record matches the bundle. In the Dockerfile image the record still describes the bundle from *before* the CA was added, and the trust-anchor rule compares the two.

Chainguard's [explanation of that rule](https://github.com/chainguard-dev/stigs/blob/main/docs/certificate-audit.md) is worth reading in full. "Approved" means *declared in a reviewed build definition*, and the recorded hash is the evidence of what was declared. A certificate added in a later layer may be perfectly legitimate, but the image can no longer prove it. For images in your own Chainguard catalog, Custom Assembly is the managed way to declare additions.

## Step 4: Gate it, with acceptances that expire

A scan that only reports gets ignored. A gate that fails on everything gets switched off. The middle ground is a short policy file in which every accepted failure has a reason, an owner and an expiry date:

```json
{
  "check": "oval:org.OpenSsl:def:1",
  "applies_to": "non-fips",
  "reason": "FIPS-validated cryptography (SV-203739, SV-203776, ...) needs a -fips image variant, which requires a FIPS entitlement. ...",
  "owner": "platform-security",
  "expires": "2027-01-31"
}
```

```text
PASS  cgr.dev/chainguard/wolfi-base:latest sha256:74e1bcf75056  pass 86  fail 5  n/a 107  unaccepted or expired 0
FAIL  drift/corporate-ca-dockerfile:local sha256:21044851f10d  pass 85  fail 6  n/a 107  unaccepted or expired 1
EXPIRED  acceptance of oval:org.OpenSsl:def:1 expired 2027-01-31 (owner platform-security): review it or remove it
```

The last line is the same image, evaluated as if it were 1 February 2027. The acceptance lapsed, so the gate fails until someone re-approves or removes it. That's a risk register entry with a review date, enforced by CI. An entry marked `non-fips` also doesn't cover an image scanned as FIPS, so a FIPS image can't quietly inherit a non-FIPS exception.

## Step 5: Sign the receipt

A checksum proves a file wasn't damaged. It doesn't prove who produced it, or which image it describes. The CI workflow builds the apko CA image, pushes it to GHCR, scans it by digest, gates it, and attests the receipt to the image digest with cosign keyless. Then anyone can verify it:

```bash
cosign verify-attestation \
  --type https://github.com/sathpal/chainguard-dashboards-end-to-end/stig-receipt/v1 \
  --certificate-identity https://github.com/sathpal/chainguard-dashboards-end-to-end/.github/workflows/compliance.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/sathpal/chainguard-dashboards-end-to-end/corp-base@sha256:2dce6a73...
```

```text
subject ghcr.io/sathpal/chainguard-dashboards-end-to-end/corp-base@sha256:2dce6a73f437...
digest  sha256:36941fa0d16b432b4e5b97fc78bd80c1d41f833ec3fed72a151e63f92d7ed7e2 linux/amd64
scanner cgr.dev/chainguard/openscap@sha256:81361810fdd51d202f6318ddc2d8410dbe7cfa2e48b1b36c93dab40851d52a50
counts  {"fail":5,"notapplicable":107,"pass":86}
```

Change the identity to any other workflow and it's refused: `expected SAN value ".../other.yml@refs/heads/main", got ".../compliance.yml@refs/heads/main"`.

One surprise: **two receipts, one digest.** apko builds are reproducible, so the second CI run rebuilt the identical image and attested a second scan to it. Receipts pile up on the artifact as a scan history, the same idea as the historical reports in the Compliance tab.

## Step 6: Insights, approximated

Insights will inventory every image your GitHub repositories reference (Dockerfiles, Helm charts, Kubernetes manifests) and show the Chainguard equivalent and the CVE difference. It isn't out yet, so I approximated it on a small sample estate with an inventory script, grype and dfc:

```text
IMAGE                               CHAINGUARD EQUIVALENT                CVES NOW (C/H/T)   AFTER (C/H/T)
cgr.dev/chainguard/go:latest        (already Chainguard)                 0/0/0              -
cgr.dev/chainguard/static:latest    (already Chainguard)                 0/0/0              -
nginx:1.27                          cgr.dev/chainguard/nginx:latest      38/235/672         0/0/0
postgres:16                         cgr.dev/chainguard/postgres:latest   3/88/309           0/0/0
python:3.12-slim                    cgr.dev/chainguard/python:latest     0/55/172           0/0/2

potential reduction for images with an equivalent: 1153 -> 2 CVEs
```

Be fair with these numbers. The estate pins tags teams commonly leave in place; at today's upstream tags (nginx 1.30.5, postgres 18.6, python:slim) the total is 774, not 1,153. The public catalog also serves `:latest` only, so this compares Python 3.12 with Chainguard's latest Python. An organisation's catalog, which Insights will use, matches versions. Either way, the gap is the story.

## Caveats nobody puts on the slide

- **This isn't the Console.** My receipts are signed by my workflow, for images I build. The Compliance tab's are signed by Chainguard, for images Chainguard builds. You want both.
- **FIPS needs an entitlement.** I couldn't reproduce the FIPS certificate panel, and every non-FIPS image fails five rules because of it. Say so in a policy file with an expiry instead of hiding it.
- **The scanner is privileged.** `oscap-docker` needs the Docker socket and the host's pid namespace. Run it on a build host, never on a production node.
- **"Not applicable" isn't "compliant".** 107 rules are for your host and runtime to meet.
- **There's no container STIG.** Chainguard applies the GPOS SRG to containers, which is the established approach, and says so in [its docs](https://edu.chainguard.dev/chainguard/containers/security-and-compliance/stigs/).

## Failures I hit along the way

| What happened | Why | Fix |
|---|---|---|
| apko: `x509: invalid ECDSA parameters` | macOS LibreSSL's `req -newkey ec` wrote explicit curve parameters; Go only accepts named curves | `openssl ecparam -name prime256v1 -genkey`, then `req -new -x509 -key` |
| Local builds were looked up on Docker Hub | Docker's containerd image store gives local builds a `RepoDigests` entry too | Ask the registry first, fall back to the local image ID |
| `drift/baseline:local` became `drift/baselineocal` | zsh read `$f:l` as its lowercase modifier | `${f}:local` |
| The CI drift step failed, and the pipe hid it | Actions' default bash has no `pipefail` | `set -o pipefail` in the step |
| The gate passed when an option arrived malformed | It ignored arguments it didn't recognise | A gate must reject what it doesn't understand |

## Good to know

- `xccdf_basic_profile_.check` is the profile ID in Chainguard's datastream. `oscap-docker image` scans without running the image; `oscap-docker container` scans a running one.
- Chainguard's stigs repository has an end-to-end test fixture per rule. Three of my fixtures follow its patterns.
- The scan was identical rule for rule on arm64 (Docker Desktop) and amd64 (GitHub Actions) for every fixture.
- [chainguard-inspec](https://github.com/chainguard-dev/chainguard-inspec) exists if your team already lives in InSpec.

## If you adopt it

1. Look at the Compliance tab for the images you pull; download the XCCDF for your assessor.
2. Scan **your** images, the ones built on top, by digest, in CI.
3. Declare additions (CAs, packages) in the build definition, not in later layers.
4. Keep accepted failures in a file with owners and expiry dates, and gate on it.
5. Attest the receipt to the digest, and verify it at deploy time against the workflow identity.
6. Re-scan on a schedule: the base image changes even when your tag doesn't.

## Try it yourself

The repository has a [step-by-step hands-on guide](https://github.com/sathpal/chainguard-dashboards-end-to-end/blob/main/docs/hands-on.md). Part A runs on a laptop with Docker in about 20 minutes, with no Chainguard account. Part B forks the repository and adds the signed receipt in GitHub Actions. Every number above is in [`evidence/`](https://github.com/sathpal/chainguard-dashboards-end-to-end/tree/main/evidence).

The short version: the Compliance Dashboard tells you the image Chainguard shipped is in good shape and gives you the evidence to prove it. The image you deploy is the one you built on top. Scan it the same way, gate it, and sign what you found.

*All numbers are from runs on 11 October 2026. Chainguard rebuilds continuously, so digests will differ; the pattern won't.*
