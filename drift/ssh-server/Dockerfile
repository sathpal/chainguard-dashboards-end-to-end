# A remote-access daemon added "for debugging". The remote-access rules fail as soon as the package is installed,
# whether or not it ever runs.
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:c2a4815b6ca49b9bbafd451b4bde690d567a86b2b6b54877faac8082a7bc4296
USER root
RUN apk add --no-cache dropbear
