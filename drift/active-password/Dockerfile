# A local account with a usable password, added for a legacy health check. Chainguard images ship only locked
# accounts; one unlocked password field fails the password rule (SV-203629).
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:c2a4815b6ca49b9bbafd451b4bde690d567a86b2b6b54877faac8082a7bc4296
USER root
RUN printf 'svc-health:ZZx/p0vU8jVbA:19000:0:99999:7:::\n' >> /etc/shadow
