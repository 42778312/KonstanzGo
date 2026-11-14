# KonstanzGo Live. Build from the repository root (the server needs Packages/KGLiveAPI and the timetable):
#   docker build -f Server/Dockerfile -t konstanzgo-live .

# --- Build ---
FROM swift:6.2-noble AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src

# Dependencies first, so a code change doesn't fetch them again.
COPY Packages/KGLiveAPI Packages/KGLiveAPI
COPY Server/Package.swift Server/Package.resolved Server/
RUN cd Server && swift package resolve

COPY Server/Sources Server/Sources
COPY Server/Tests Server/Tests
ARG LIVE_VERSION=dev
RUN cd Server \
    && swift build -c release --product Run --static-swift-stdlib \
       -Xlinker -s \
    && mkdir -p /staging/lib \
    && cp "$(swift build -c release --show-bin-path)/Run" /staging/live \
    # The two system libraries the runtime image lacks.
    && cp -L $(ldd /staging/live | awk '/libsqlite3|libz\./ {print $3}') /staging/lib/

# --- Run ---
# Distroless: glibc, the C++ runtime, CA certificates and time zones; no shell, no package manager.
FROM gcr.io/distroless/cc-debian13:nonroot
ARG LIVE_VERSION=dev
ENV TZ=Europe/Berlin \
    PORT=8080 \
    TIMETABLE_PATH=/app/data/timetable.db \
    LD_LIBRARY_PATH=/app/lib \
    LOG_LEVEL=info \
    LIVE_VERSION=${LIVE_VERSION}
WORKDIR /app
COPY --from=build /staging/lib/ /app/lib/
COPY --from=build /staging/live /app/live
# Owned by root, readable by the nonroot user that runs the server, writable by nobody.
COPY App/Resources/Data/timetable.db /app/data/timetable.db
USER nonroot
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/app/live", "healthcheck"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/live"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0"]
