# A package mirror added over plain http: package downloads lose transport integrity, and the package-signature rule
# (SV-203720) fails. Seen in practice when an internal mirror is added during a proxy migration.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:1c451d46a0d5c4e9f2b38e0e8d3e299564a1aa95c21973efcc1980a9d1d2e73e
USER root
RUN printf '# internal mirror\nhttp://mirror.example.internal/wolfi\n' >> /etc/apk/repositories
