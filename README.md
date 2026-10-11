# Chainguard dashboards, end to end

Chainguard shipped two dashboards in its Console in the week of 6 October 2026:

| Dashboard | Status (11 October 2026) | What it shows |
|---|---|---|
| [Compliance Dashboard](https://www.chainguard.dev/unchained/announcing-the-chainguard-compliance-dashboard) | **Generally available** since 7 October, "for all Chainguard Console users" | Per image: DISA STIG results against the General Purpose OS SRG, downloadable XCCDF reports, FIPS 140-3 module and entropy-source certificate numbers, and signed validation receipts tied to the exact tag, architecture and digest. Updated with every image build. |
| [Insights Dashboard](https://www.chainguard.dev/unchained/introducing-the-chainguard-console-insights-dashboard-powered-by-guardener) | **Announced** 8 October, "available in the coming weeks"; [Guardener](https://edu.chainguard.dev/chainguard/guardener/github/getting-started/), which feeds it, is in Early Access | Every container image your GitHub repositories reference (Dockerfiles, Helm charts, Kubernetes manifests), the Chainguard equivalent, the CVE difference, and migration pull requests. |

This repository does not show the Console. It reproduces each piece of evidence those dashboards present, with
public images and open tools, so you can check it, automate it in CI, and extend it to the images **you** build on
top of Chainguard's, which is where the dashboards stop. Everything below was run on 11 October 2026, on a laptop
(linux/arm64) and in GitHub Actions (linux/amd64); the drift fixtures gave the same result for every rule on both.

**Start here: [the hands-on guide](docs/hands-on.md)**: every command, what it prints, and what it proves.

## What each panel is, and how it is reproduced here

| In the Console | Reproduced here by | Needs |
|---|---|---|
| STIG results (pass, fail, not applicable per rule) | [`scripts/stig-scan.sh`](scripts/stig-scan.sh): Chainguard's own `openscap` image and GPOS profile, run against an image pinned by digest | Docker |
| XCCDF download with a SHA-256 to check | `results.xml` and `results.xml.sha256` from every scan | - |
| Signed validation receipt for tag, architecture, digest | `receipt.json`, attested to the image digest with cosign keyless in [CI](.github/workflows/compliance.yml), verified against the workflow identity | GitHub Actions, GHCR |
| Status that follows every image build | A weekly scheduled scan: same tag, new digest, new receipt | GitHub Actions |
| FIPS 140-3 certificates and entropy source | Not reproduced: needs a `-fips` image, which needs a FIPS entitlement. The guide shows Chainguard's documented checks | FIPS entitlement |
| *Not in the Console:* what your own changes do | [`scripts/drift.sh`](scripts/drift.sh) and [`drift/`](drift/): five customisations teams commonly make, scanned against the image as shipped | Docker |
| *Not in the Console:* failures you have accepted | [`scripts/gate.py`](scripts/gate.py) and [`policy/accepted-failures.json`](policy/accepted-failures.json): each acceptance has a reason, an owner and an expiry | - |
| Insights: inventory, equivalent, CVE difference | [`scripts/insights.sh`](scripts/insights.sh) on the sample [`estate/`](estate/), with grype and dfc | grype, dfc |

## Results at a glance

**Chainguard images as shipped** pass 86 rules, 107 do not apply to a container, and 5 fail. All 5 failures are one
check, `oval:org.OpenSsl:def:1`: FIPS-validated cryptography, which only a `-fips` variant can pass. That is why
the Compliance tab is built around FIPS images. The same result on `wolfi-base`, `python` and `nginx`, on both
architectures ([`dashboard.md`](evidence/dashboard.md)).

**What your own changes do** ([`drift.txt`](evidence/drift.txt)):

| Customisation on top of Chainguard `wolfi-base` | Rules that change from pass to fail |
|---|---|
| Corporate root CA added in a Dockerfile with `update-ca-certificates` | 1: SV-263659, only approved trust anchors |
| **The same CA declared in the apko build definition** | **none** |
| Internal package mirror over plain `http` | 1: SV-203720 (high), package signature verification |
| An SSH server (`dropbear`) installed "for debugging" | 46: every remote-access requirement |
| A local account with a usable password | 31: password and account requirements |

The two CA images trust exactly the same 122 roots and have byte-identical bundles. Only one can prove its bundle is
the approved one: apko writes the bundle's SHA-256 after merging declared certificates, and the scan compares
against it. A later `update-ca-certificates` leaves that record stale.

**Signed receipt** ([`receipt-verify.txt`](evidence/receipt-verify.txt)): CI built the apko image, pushed it to
GHCR, scanned it by digest, gated it, and attested the receipt. `cosign verify-attestation` on a laptop accepts it for
`compliance.yml@refs/heads/main` and refuses it for any other workflow identity.

**Insights, approximated** ([`insights.txt`](evidence/insights.txt)): the sample estate references five images in a
Dockerfile, a Helm chart and a StatefulSet. The three upstream images carry 1,153 CVEs (41 critical) at the tags the
estate pins, and 774 at today's upstream tags ([`insights-current-tags.txt`](evidence/insights-current-tags.txt)). Their
public Chainguard equivalents carry 2, neither critical nor high.

## Run it

```bash
git clone https://github.com/sathpal/chainguard-dashboards-end-to-end && cd chainguard-dashboards-end-to-end
scripts/stig-scan.sh cgr.dev/chainguard/wolfi-base:latest out/wolfi-base     # one image, about 10 seconds
python3 scripts/gate.py out/wolfi-base/receipt.json policy/accepted-failures.json
scripts/drift.sh                                                               # five fixtures, about a minute
scripts/insights.sh estate                                                     # about four minutes, mostly grype pulls
```

Needs Docker, `crane`, Python 3 and, for Insights, `grype`, `jq` and optionally `dfc`. No Chainguard account: every
image used is in the public `cgr.dev/chainguard` catalog. Fork the repository and the
[workflow](.github/workflows/compliance.yml) runs the same on GitHub, adds the signed receipt, and repeats weekly.

## What is here

```text
scripts/stig-scan.sh     scan one image by digest; write results.xml, its SHA-256, report.html and receipt.json
scripts/stig-summary.py  read XCCDF results: counts, failed rules, diff against a baseline (standard library only)
scripts/gate.py          pass or fail a receipt against accepted failures that expire
scripts/dashboard.py     render receipts as a Markdown table, the overview the Console gives per image
scripts/drift.sh         build each fixture in drift/, scan it, show what changed against the baseline
scripts/insights.sh      inventory an estate's images, find Chainguard equivalents, compare CVEs, propose migrations
scripts/inventory.py     find image references in Dockerfiles, Kubernetes manifests and Helm values
drift/                   baseline + five customisations (four Dockerfiles, one apko.yaml) and a throwaway test CA
estate/                  a sample application estate: a Dockerfile service, a Helm chart, a StatefulSet
policy/                  accepted-failures.json
evidence/                every result quoted in this README
.github/workflows/       compliance.yml: scan, gate, drift, signed receipt; Chainguard Actions pinned by SHA
```

## What this does not show

- **The Console itself.** Nothing here logs in to Chainguard. The Compliance tab's receipts are signed by Chainguard;
  the receipts here are signed by this repository's workflow, for images it builds.
- **FIPS.** The FIPS certificate panel, and the 5 rules every non-FIPS image fails, need `-fips` images and a FIPS
  entitlement. The accepted-failures policy says so, with an expiry, instead of hiding it.
- **Insights' real numbers.** The public catalog serves `:latest` only, so `python:3.12-slim` is compared with
  Chainguard's latest Python, not 3.12. An organisation's catalog matches versions.
- **A container STIG.** DISA has never published a container SRG; Chainguard's profile applies the GPOS SRG to
  containers, the established approach ([Chainguard's STIG documentation](https://edu.chainguard.dev/chainguard/containers/security-and-compliance/stigs/)).
  107 of 198 rules report not applicable, each with a rationale in the report; most are controls that belong to the
  host or the runtime, such as audit, time, firewall and ASLR.

## References

- [Announcing the Chainguard Compliance Dashboard](https://www.chainguard.dev/unchained/announcing-the-chainguard-compliance-dashboard) (7 October 2026)
- [Introducing the Chainguard Console Insights Dashboard, powered by Guardener](https://www.chainguard.dev/unchained/introducing-the-chainguard-console-insights-dashboard-powered-by-guardener) (8 October 2026)
- [STIGs for Chainguard Containers](https://edu.chainguard.dev/chainguard/containers/security-and-compliance/stigs/) and [chainguard-dev/stigs](https://github.com/chainguard-dev/stigs), including [how added trust anchors stay verifiable](https://github.com/chainguard-dev/stigs/blob/main/docs/certificate-audit.md)
- [Verifying FIPS configuration](https://edu.chainguard.dev/platform/fips/verify-fips/)
- [Chainguard Actions, end to end](https://github.com/sathpal/chainguard-actions-end-to-end): the hardened actions this workflow uses
