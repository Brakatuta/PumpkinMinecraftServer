FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    procps \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory for persistent server data
WORKDIR /data

# Copy and set entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose Minecraft server ports:
# 25565/tcp : Java Edition
# 19132/udp : Bedrock Edition
# 19133/udp : Bedrock IPv6 status
# 4445/udp  : Minecraft LAN Broadcast
EXPOSE 25565/tcp 19132/udp 19133/udp 4445/udp

# Persistent storage mount point
VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
