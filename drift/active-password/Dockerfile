# A local account with a usable password, added for a legacy health check. Chainguard images ship only locked
# accounts; one unlocked password field fails the password rule (SV-203629).
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:1c451d46a0d5c4e9f2b38e0e8d3e299564a1aa95c21973efcc1980a9d1d2e73e
USER root
RUN printf 'svc-health:ZZx/p0vU8jVbA:19000:0:99999:7:::\n' >> /etc/shadow
