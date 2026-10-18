# A package mirror added over plain http: package downloads lose transport integrity, and the package-signature rule
# (SV-203720) fails. Seen in practice when an internal mirror is added during a proxy migration.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:c2a4815b6ca49b9bbafd451b4bde690d567a86b2b6b54877faac8082a7bc4296
USER root
RUN printf '# internal mirror\nhttp://mirror.example.internal/wolfi\n' >> /etc/apk/repositories
