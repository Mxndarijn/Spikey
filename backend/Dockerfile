# The game server's image. Build from the repository root (it needs the Rust
# sim next to backend/):
#   docker build -f backend/Dockerfile --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t <REGISTRY>/flapjaw-server:<sha> .
# tools/deploy.ps1 does this. Only x86-64 (amd64) is built.
FROM rust:1.90-bookworm AS build
WORKDIR /src
COPY tools/fastsim-rs tools/fastsim-rs
COPY backend backend
RUN cargo build --release --locked --manifest-path backend/Cargo.toml

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/backend/target/release/flapjaw-server /usr/local/bin/flapjaw-server
ARG GIT_SHA=dev
ENV GIT_SHA=$GIT_SHA LISTEN=0.0.0.0:8080 RUST_LOG=info
USER 10001
EXPOSE 8080
ENTRYPOINT ["flapjaw-server"]
