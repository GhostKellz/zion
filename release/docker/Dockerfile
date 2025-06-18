FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    zig \
    git \
    curl \
    tar \
    bash

# Set working directory
WORKDIR /workspace

# Clone and build Zion
RUN git clone https://github.com/ghostkellz/zion.git /tmp/zion \
    && cd /tmp/zion \
    && zig build -Doptimize=ReleaseSafe \
    && cp zig-out/bin/zion /usr/local/bin/zion \
    && rm -rf /tmp/zion

# Create a non-root user
RUN adduser -D -s /bin/bash zion

# Switch to non-root user
USER zion

# Set the entrypoint
ENTRYPOINT ["zion"]
CMD ["help"]