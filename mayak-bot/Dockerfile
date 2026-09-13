# mayak-bot/Dockerfile

# Debian-based, not musl/Alpine: rustls's default crypto backend
# (aws-lc-rs) needs cmake + a C compiler to build, and cross-compiling
# that through musl is a known source of flaky builds. This only affects
# the build stage - the final binary has zero C dependencies at runtime.
FROM rust:1-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends cmake \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Cache dependency compilation separately from source changes. teloxide
# alone pulls in ~200 transitive crates - without this, editing one line
# of your own code would force recompiling all of them on every build.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
RUN touch src/main.rs && cargo build --release

# No ca-certificates needed: rustls + webpki-roots bakes CA certs into
# the binary itself, unlike native-tls which reads the OS trust store.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/mayak-bot /usr/local/bin/mayak-bot
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/mayak-bot"]
