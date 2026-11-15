# Headless Godot that has the last word on runs the Rust check rejected (the
# godot-check CronJob, deploy/base/godot-check.yaml). Build from the repository
# root:
#   docker build -f deploy/godot-check/Dockerfile -t <REGISTRY>/flapjaw-godot-check:<sha> .
# It runs server/verify_batch.gd, the same GDScript checker the game's sim/ is.
FROM debian:bookworm-slim
ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip postgresql-client libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip
WORKDIR /game
COPY . /game
# The class cache; the first import sometimes stops early, the second finishes.
RUN godot --headless --path /game --import || godot --headless --path /game --import
COPY deploy/godot-check/check.sh /usr/local/bin/check.sh
RUN chmod +x /usr/local/bin/check.sh && useradd -u 10002 -m checker && chown -R checker /game
USER 10002
ENTRYPOINT ["/usr/local/bin/check.sh"]
