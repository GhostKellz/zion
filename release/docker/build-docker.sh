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

# Build the image
docker build -t ghostkellz/zion:latest .

echo -e "${GREEN}Docker image built successfully!${NC}"
echo -e "You can now run: docker run --rm ghostkellz/zion:latest"
echo -e "Or for interactive use: docker run -it --rm -v \$(pwd):/workspace ghostkellz/zion:latest bash"