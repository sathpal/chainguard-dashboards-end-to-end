# The common way teams add a corporate root CA: copy it in and run update-ca-certificates in a derived layer.
# The bundle changes after apko recorded its SHA-256 in /etc/ssl/certs/.ca-certificates.crt.sha256, so the
# trust-anchor rule (SV-263659, CCI-004909: only approved trust anchors) can no longer prove the bundle is the
# approved one, and fails. Compare corporate-ca-apko, which adds the same certificate at build time and passes.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:c2a4815b6ca49b9bbafd451b4bde690d567a86b2b6b54877faac8082a7bc4296
USER root
RUN apk add --no-cache ca-certificates
COPY corp-root.crt /usr/local/share/ca-certificates/example-corp-root.crt
RUN update-ca-certificates
