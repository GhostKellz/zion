FROM debian:trixie-slim

COPY zig-out/bin/zion /usr/local/bin/zion
COPY README.md /usr/share/doc/zion/README.md
COPY LICENSE /usr/share/licenses/zion/LICENSE
COPY .scratch/zion.1 /usr/share/man/man1/zion.1

RUN useradd --create-home --shell /usr/sbin/nologin zion
USER zion

# Set the entrypoint
ENTRYPOINT ["zion"]
CMD ["help"]
