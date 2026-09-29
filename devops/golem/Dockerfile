# Use a lightweight base image
FROM debian:bookworm-slim

# Install necessary dependencies (curl to download the binary, ca-certificates for HTTPS)
RUN apt-get update && apt-get install -y curl ca-certificates && rm -rf /var/lib/apt/lists/*

# Set up environment variables
ENV GOLEM_VERSION=1.5.10
ENV DATA_DIR=/data/golem
ENV ROUTER_PORT=9881
ENV CUSTOM_REQUEST_PORT=9006
ENV MCP_PORT=9007

# Create directory for Golem data
RUN mkdir -p ${DATA_DIR}

# Download and install the golem single binary
# The 'golem' binary is a superset of the CLI and includes the built-in local server
RUN curl -L -o /usr/local/bin/golem https://github.com/golemcloud/golem/releases/download/v${GOLEM_VERSION}/golem-x86_64-unknown-linux-gnu && \
    chmod +x /usr/local/bin/golem

# Expose the ports used by the golem server
EXPOSE ${ROUTER_PORT} ${CUSTOM_REQUEST_PORT} ${MCP_PORT}

# Set the data directory as a volume
VOLUME ${DATA_DIR}

# Start the golem server using the exact syntax from the docs
ENTRYPOINT ["golem", "server", "run"]
CMD ["--router-port", "9881", "--custom-request-port", "9006", "--mcp-port", "9007", "--data-dir", "/data/golem"]
