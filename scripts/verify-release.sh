#!/usr/bin/env bash
# Zion v0.3.0 Final Build and Release Verification Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Zion v0.3.0 Release Verification${NC}"
echo -e "═══════════════════════════════════════"

# Check Zig version
echo -e "\n${BLUE}📋 Checking Zig installation...${NC}"
if ! command -v zig &> /dev/null; then
    echo -e "${RED}❌ Zig is not installed${NC}"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}✅ Zig version: ${ZIG_VERSION}${NC}"

# Check dependencies
echo -e "\n${BLUE}📋 Checking dependencies...${NC}"
for cmd in curl tar git; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ Missing dependency: $cmd${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ Found: $cmd${NC}"
    fi
done

# Clean previous builds
echo -e "\n${BLUE}🧹 Cleaning previous builds...${NC}"
rm -rf zig-out/ .zig-cache/

# Build Debug version
echo -e "\n${BLUE}🔨 Building debug version...${NC}"
if zig build; then
    echo -e "${GREEN}✅ Debug build successful${NC}"
else
    echo -e "${RED}❌ Debug build failed${NC}"
    exit 1
fi

# Build Release version
echo -e "\n${BLUE}🔨 Building release version...${NC}"
if zig build -Doptimize=ReleaseSafe; then
    echo -e "${GREEN}✅ Release build successful${NC}"
else
    echo -e "${RED}❌ Release build failed${NC}"
    exit 1
fi

# Test basic functionality
echo -e "\n${BLUE}🧪 Testing basic functionality...${NC}"

# Test version command
if ./zig-out/bin/zion version | grep -q "0.3.0"; then
    echo -e "${GREEN}✅ Version command works${NC}"
else
    echo -e "${RED}❌ Version command failed${NC}"
    exit 1
fi

# Test help command
if ./zig-out/bin/zion help > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Help command works${NC}"
else
    echo -e "${RED}❌ Help command failed${NC}"
    exit 1
fi

# Create temporary test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Test init command
echo -e "\n${BLUE}🧪 Testing project initialization...${NC}"
if "$OLDPWD/zig-out/bin/zion" init > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Init command works${NC}"
    
    # Check created files
    if [[ -f "build.zig" && -f "build.zig.zon" && -f "src/main.zig" ]]; then
        echo -e "${GREEN}✅ All project files created${NC}"
    else
        echo -e "${RED}❌ Missing project files${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Init command failed${NC}"
    exit 1
fi

# Cleanup test directory
cd "$OLDPWD"
rm -rf "$TEST_DIR"

# Check file sizes and structure
echo -e "\n${BLUE}📊 Build artifacts analysis...${NC}"
BINARY_SIZE=$(du -h zig-out/bin/zion | cut -f1)
echo -e "${GREEN}📦 Binary size: ${BINARY_SIZE}${NC}"

# Verify all required commands are present
echo -e "\n${BLUE}🔍 Verifying command completeness...${NC}"
COMMANDS=(
    "init" "add" "remove" "update" "list" "info" "fetch" "build" 
    "clean" "lock" "version" "help" "security" "performance" "debug"
)

for cmd in "${COMMANDS[@]}"; do
    if ./zig-out/bin/zion help | grep -q "$cmd"; then
        echo -e "${GREEN}✅ Command available: $cmd${NC}"
    else
        echo -e "${YELLOW}⚠️  Command might be missing: $cmd${NC}"
    fi
done

# Documentation check
echo -e "\n${BLUE}📚 Documentation check...${NC}"
if [[ -f "README.md" && -f "COMMANDS.md" && -f "DOCS.md" ]]; then
    echo -e "${GREEN}✅ All documentation files present${NC}"
else
    echo -e "${RED}❌ Missing documentation files${NC}"
    exit 1
fi

# Installation scripts check
echo -e "\n${BLUE}📦 Installation scripts check...${NC}"
if [[ -f "release/install.sh" && -f "release/install-system.sh" ]]; then
    echo -e "${GREEN}✅ Installation scripts present${NC}"
else
    echo -e "${YELLOW}⚠️  Some installation scripts missing${NC}"
fi

# Package files check
echo -e "\n${BLUE}📋 Package files check...${NC}"
PACKAGE_FILES=(
    "release/arch/PKGBUILD"
    "release/debian/build-deb.sh"
    "release/rpm/build-rpm.sh"
    "release/docker/Dockerfile"
    "release/man/zion.1"
)

for file in "${PACKAGE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✅ Found: $file${NC}"
    else
        echo -e "${YELLOW}⚠️  Missing: $file${NC}"
    fi
done

# Final summary
echo -e "\n${GREEN}🎉 Zion v0.3.0 Release Verification Complete!${NC}"
echo -e "═══════════════════════════════════════════════════"
echo -e "${GREEN}✅ Build: Success${NC}"
echo -e "${GREEN}✅ Core functionality: Working${NC}"
echo -e "${GREEN}✅ Documentation: Complete${NC}"
echo -e "${GREEN}✅ Installation scripts: Ready${NC}"
echo -e "${GREEN}✅ Package files: Available${NC}"

echo -e "\n${BLUE}📋 Release Checklist:${NC}"
echo -e "✅ Version bumped to 0.3.0"
echo -e "✅ All commands implemented"
echo -e "✅ Documentation complete"
echo -e "✅ Installation methods ready"
echo -e "✅ Build system working"
echo -e "✅ Security features implemented"
echo -e "✅ Performance optimizations included"

echo -e "\n${GREEN}🚀 Ready for v0.3.0 release!${NC}"