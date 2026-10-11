FROM cgr.dev/chainguard/go:latest AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/ledger .

FROM cgr.dev/chainguard/static:latest
COPY --from=build /out/ledger /ledger
ENTRYPOINT ["/ledger"]
