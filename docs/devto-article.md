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
- **A free-tier Console organisation doesn't get the Compliance tab**, not even on `python-fips`. The catalog shows "FIPS validated" and "STIG hardened" badges; the evidence behind them is for images in an organisation's own registry.
- **Chainguard images as shipped:** 86 rules pass, 107 don't apply to a container, 5 fail. All 5 failures are one check, FIPS-validated cryptography, which only a `-fips` image can pass. Same result on `wolfi-base`, `python` and `nginx`, on arm64 and amd64.
- **What you add on top is where compliance breaks.** An SSH server fails 46 rules. A plain-http package mirror fails a high-severity rule. A corporate CA added with `update-ca-certificates` fails the trust-anchor rule; the same CA declared in the apko build definition passes.
- **A receipt is only useful signed.** CI scans the image by digest, gates the result, and attests the receipt to the digest with cosign. It verifies for that workflow and is refused for any other.
- **Insights, approximated:** three upstream images in a sample estate carry 1,153 CVEs at the tags the estate pins, 774 at today's tags. Their public Chainguard equivalents carry 2.

## What the Compliance Dashboard shows

![Chainguard blog: Announcing the Chainguard Compliance Dashboard, 7 October 2026](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/web-compliance-post.png)

For each image in your organisation's catalog, the Console's Compliance tab shows:

- DISA STIG results against the General Purpose Operating System SRG, rule by rule.
- The XCCDF report, to download and check against its SHA-256.
- FIPS 140-3 module and entropy-source certificate numbers.
- Signed validation receipts tied to the exact tag, architecture and digest that was evaluated.

It updates with every image build, and the announcement lists Custom Assembly support as a fast follow. All of that is evidence an assessor can use, produced by Chainguard for the images Chainguard builds.

I signed in to the Console with a free-tier organisation to see it for myself. The catalog lists `-fips` variants with "FIPS validated" and "STIG hardened" badges, but the image pages have eight tabs (Tags, Overview, Comparison, Provenance, Specifications, SBOM, Vulnerabilities, Advisories) and no Compliance tab, not even on `python-fips`. Chainguard's documentation for the tab, still in review, describes it for an organisation's FIPS images, so it appears for images in your own registry, not for the public catalog.

![Chainguard Console, free-tier organisation: python-fips with FIPS validated and STIG hardened badges, eight tabs, no Compliance tab](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/console-python-fips.png)
*python-fips in the Console on a free-tier organisation: the badges are there, the Compliance tab is not.*

So I asked a different question: can I produce each of those pieces myself, for any image, in CI? It turns out you can, with Chainguard's own scanner image.

## Step 1: Scan a Chainguard image the way the Compliance tab does

Chainguard publishes its STIG profile in [chainguard-dev/stigs](https://github.com/chainguard-dev/stigs) and ships it inside a public `openscap` image. A short script pins the target to a digest, runs `oscap-docker` against it, and writes the report, the XCCDF results, a checksum and a receipt:

```bash
scripts/stig-scan.sh cgr.dev/chainguard/wolfi-base:latest out/wolfi-base
```

![stig-scan.sh on cgr.dev/chainguard/wolfi-base: 198 rules, 86 pass, 107 not applicable, 5 fail, all five from oval:org.OpenSsl:def:1](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/stig-scan.png)

Ten seconds, and three things to read in it.

**The five failures are one check.** `oval:org.OpenSsl:def:1` asserts that the OpenSSL FIPS provider and its hardened configuration are installed and enabled. A non-FIPS image can't pass it, by design. That is why the Compliance tab is built around an organisation's FIPS images, and why the FIPS panel needs a FIPS entitlement I don't have.

**107 rules are "not applicable".** DISA has never published a container SRG, so Chainguard applies the OS-level one and marks the requirements that belong to the host or runtime, such as audit offloading, time sync, wireless and firewall. When an assessor asks about those, the answer is your node's STIG, not the image's.

**Everything is pinned.** The tag became a digest before the scan, and the scanner ran by digest too. Both go into `receipt.json` with the profile's SHA-256, the results file's SHA-256, the timestamps and the counts. A result that names a tag describes something that will be different tomorrow.

## Step 2: Scan what you build on top

This is the part no vendor dashboard can cover: almost nobody runs a base image unmodified. I wrote five fixtures, each a few lines on top of the same pinned `wolfi-base`, modelled on common customisations (three follow test fixtures in Chainguard's own STIG repository), and diffed each scan against the unmodified image:

![drift.sh: each customisation on top of wolfi-base and the rules it turns from pass to fail](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/drift.png)

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

![Recorded SHA-256 against the CA bundle in three images: baseline matches, the Dockerfile CA image is stale, the apko CA image matches](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/ca-sidecars.png)

Both CA images trust the same 122 roots, byte for byte. In the apko image the record matches the bundle. In the Dockerfile image the record still describes the bundle from *before* the CA was added, and the trust-anchor rule compares the two.

Chainguard's [explanation of that rule](https://github.com/chainguard-dev/stigs/blob/main/docs/certificate-audit.md) is worth reading in full.

![chainguard-dev/stigs certificate-audit.md: how additional trust anchors reach the sidecars](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/web-cert-audit-doc.png) "Approved" means *declared in a reviewed build definition*, and the recorded hash is the evidence of what was declared. A certificate added in a later layer may be perfectly legitimate, but the image can no longer prove it. For images in your own Chainguard catalog, Custom Assembly is the managed way to declare additions.

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

![gate.py: PASS with accepted FIPS failures, FAIL on the Dockerfile CA image, EXPIRED acceptance in 2027, FAIL when the image is treated as FIPS](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/gate.png)

The third run is the same image, evaluated as if it were 1 February 2027. The acceptance lapsed, so the gate fails until someone re-approves or removes it. That's a risk register entry with a review date, enforced by CI. An entry marked `non-fips` also doesn't cover an image scanned as FIPS, so a FIPS image can't quietly inherit a non-FIPS exception.

## Step 5: Sign the receipt

A checksum proves a file wasn't damaged. It doesn't prove who produced it, or which image it describes. The CI workflow builds the apko CA image, pushes it to GHCR, scans it by digest, gates it, and attests the receipt to the image digest with cosign keyless. Then anyone can verify it:

```bash
cosign verify-attestation \
  --type https://github.com/sathpal/chainguard-dashboards-end-to-end/stig-receipt/v1 \
  --certificate-identity https://github.com/sathpal/chainguard-dashboards-end-to-end/.github/workflows/compliance.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/sathpal/chainguard-dashboards-end-to-end/corp-base@sha256:2dce6a73...
```

![cosign verify-attestation: four signed receipts on one image digest, accepted for compliance.yml and refused for any other workflow identity](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/receipt-verify.png)

Change the identity to any other workflow and it's refused, as the last command shows.

One surprise: **four receipts, one digest.** apko builds are reproducible, so every CI run that day rebuilt the identical image and attested another scan to it. Receipts pile up on the artifact as a scan history, the same idea as the historical reports in the Compliance tab.

![GitHub Actions: the compliance workflow with three scans, drift and the signed receipt, all green](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/web-ci-run.png)

## Step 6: Insights, approximated

![Chainguard blog: Introducing the Chainguard Console Insights Dashboard, powered by Guardener, 8 October 2026](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/web-insights-post.png)

Insights will inventory every image your GitHub repositories reference (Dockerfiles, Helm charts, Kubernetes manifests) and show the Chainguard equivalent and the CVE difference. It isn't out yet, so I approximated it on a small sample estate with an inventory script, grype and dfc:

![insights.sh on the sample estate: five images, Chainguard equivalents, 1,153 CVEs down to 2, and the dfc migration](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/insights.png)

Be fair with these numbers. The estate pins tags teams commonly leave in place; at today's upstream tags (nginx 1.30.5, postgres 18.6, python:slim) the total is 774, not 1,153. The public catalog also serves `:latest` only, so this compares Python 3.12 with Chainguard's latest Python. An organisation's catalog, which Insights will use, matches versions. Either way, the gap is the story.

The Console already has a piece of this today. **Reports** (CVE Visualizations, already GA) compares a Chainguard image with an alternative over time. For nginx on 11 October it showed 0 CVEs against 191 for `nginx:latest`, a daily average of 4 against 200, and 7.4 MB against 63 MB:

![Chainguard Console Reports: nginx, Chainguard 0 CVEs and 7.38 MB against nginx:latest with 191 CVEs and 63.26 MB](https://raw.githubusercontent.com/sathpal/chainguard-dashboards-end-to-end/main/docs/images/console-reports-nginx.png)

## Caveats nobody puts on the slide

- **This isn't the Compliance tab.** My receipts are signed by my workflow, for images I build. The Compliance tab's are signed by Chainguard, for images Chainguard builds. You want both, and on a free-tier organisation you only get mine.
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
