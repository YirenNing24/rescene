FROM gcr.io/distroless/static-debian12:nonroot
COPY --chown=65532:65532 rescene-api /app/rescene-api
WORKDIR /app
USER 65532:65532
ENTRYPOINT ["/app/rescene-api"]
