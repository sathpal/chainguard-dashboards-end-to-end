# A remote-access daemon added "for debugging". The remote-access rules fail as soon as the package is installed,
# whether or not it ever runs.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:1c451d46a0d5c4e9f2b38e0e8d3e299564a1aa95c21973efcc1980a9d1d2e73e
USER root
RUN apk add --no-cache dropbear
