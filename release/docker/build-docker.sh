#!/usr/bin/env bash
# Build Docker image for Zion
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building Zion Docker image...${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/build.zig.zon" | head -1)"

cd "$REPO_ROOT"
zig build -Doptimize=ReleaseSafe
mkdir -p .scratch
sed "s/@VERSION@/$VERSION/g" release/man/zion.1 > .scratch/zion.1
trap 'rm -f "$REPO_ROOT/.scratch/zion.1"; rmdir "$REPO_ROOT/.scratch" 2>/dev/null || true' EXIT INT TERM

docker build --network none -f release/docker/Dockerfile -t "zion:$VERSION" .

echo -e "${GREEN}Docker image built successfully!${NC}"
docker run --rm --network none "zion:$VERSION" version
