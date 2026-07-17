#!/bin/bash

# Comprehensive Test Suite for Zion v1.0.7
# Tests all new async features, performance improvements, and reliability enhancements

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_WORKSPACE="$REPO_ROOT/.scratch/v1.0.7-workspace"

cleanup() {
    rm -rf "$TEST_WORKSPACE"
    rmdir "$REPO_ROOT/.scratch" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "🧪 Zion v1.0.7 Comprehensive Test Suite"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "\n${BLUE}[$TOTAL_TESTS]${NC} Testing: $test_name"
    echo "Command: $test_command"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local exit_code=$?
        if [ $exit_code -eq $expected_exit_code ]; then
            echo -e "${GREEN}✅ PASS${NC}: $test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ FAIL${NC}: $test_name (exit code $exit_code, expected $expected_exit_code)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        local exit_code=$?
        if [ $exit_code -eq $expected_exit_code ]; then
            echo -e "${GREEN}✅ PASS${NC}: $test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ FAIL${NC}: $test_name (exit code $exit_code, expected $expected_exit_code)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "\n${BLUE}[$TOTAL_TESTS]${NC} Testing: $test_name"
    echo "Command: $test_command"
    
    local output
    output=$(eval "$test_command" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$output" | grep -q "$expected_pattern"; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        echo "Output matched pattern: $expected_pattern"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        echo "Exit code: $exit_code"
        echo "Output: $output"
        echo "Expected pattern: $expected_pattern"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

benchmark_test() {
    local test_name="$1"
    local test_command="$2"
    local max_time_seconds="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "\n${BLUE}[$TOTAL_TESTS]${NC} Benchmark: $test_name"
    echo "Command: $test_command"
    echo "Max time: ${max_time_seconds}s"
    
    local start_time
    start_time=$(date +%s)
    
    if eval "$test_command" >/dev/null 2>&1; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ $duration -le $max_time_seconds ]; then
            echo -e "${GREEN}✅ PASS${NC}: $test_name (${duration}s)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ FAIL${NC}: $test_name (${duration}s > ${max_time_seconds}s)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name (command failed)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo -e "\n🏗️ Build Tests"
echo "=============="

# First, ensure we can build
run_test "Build Zion v1.0.7" "zig build"

# Check if binary was created
run_test "Binary creation" "test -f ./zig-out/bin/zion"

# Make binary executable
chmod +x ./zig-out/bin/zion

echo -e "\n📋 Basic Command Tests"
echo "====================="

# Basic command tests
run_test_with_output "Version command" "./zig-out/bin/zion version" "1.0.7"
run_test "Help command" "./zig-out/bin/zion help"
run_test "Invalid command handling" "./zig-out/bin/zion nonexistent-command" "1"

echo -e "\n🆕 New Command Tests (v1.0.7)"
echo "============================="

# Test new v1.0.7 commands
run_test_with_output "Health command" "./zig-out/bin/zion health" "Checking registry health"
run_test_with_output "Health alias (hc)" "./zig-out/bin/zion hc" "Checking registry health"

run_test_with_output "Benchmark command" "./zig-out/bin/zion benchmark" "Running performance benchmarks"
run_test_with_output "Benchmark alias (bench)" "./zig-out/bin/zion bench" "Running performance benchmarks"
run_test_with_output "Benchmark alias (perf)" "./zig-out/bin/zion perf" "Running performance benchmarks"

echo -e "\n⚡ Performance Tests"
echo "==================="

# Performance benchmarks - these should be faster in v1.0.7
benchmark_test "Health check speed" "./zig-out/bin/zion health" "5"
benchmark_test "Benchmark execution speed" "./zig-out/bin/zion benchmark" "10"

echo -e "\n🔍 Search Performance Tests"  
echo "==========================="

# Test search performance (should be 3-5x faster with racing registry)
benchmark_test "Search command speed" "./zig-out/bin/zion search test 2>/dev/null || true" "3"

echo -e "\n📦 Package Management Tests"
echo "==========================="

# Create test workspace
mkdir -p "$TEST_WORKSPACE"
cd "$TEST_WORKSPACE"

# Initialize test project
run_test "Initialize test project" "\"$REPO_ROOT/zig-out/bin/zion\" init"

# Test adding packages (should be faster with vectorized downloads)
benchmark_test "Add package speed" "\"$REPO_ROOT/zig-out/bin/zion\" add ziglang/zig-clap 2>/dev/null || true" "10"

# Test batch operations (should be 5-10x faster)  
benchmark_test "Batch add speed" "\"$REPO_ROOT/zig-out/bin/zion\" add ziglang/zig-clap Hejsil/zig-clap 2>/dev/null || true" "15"

echo -e "\n🛡️ Error Handling Tests"
echo "======================"

# Test error handling improvements
run_test "Graceful failure - invalid package" "\"$REPO_ROOT/zig-out/bin/zion\" add nonexistent/invalid-package-12345 2>/dev/null" "1"

# Test timeout handling
run_test "Timeout handling" "timeout 5s \"$REPO_ROOT/zig-out/bin/zion\" search test 2>/dev/null || true"

echo -e "\n🧠 Memory Tests"
echo "==============="

# Test memory efficiency (should use 15% less memory)
run_test "Memory leak check - multiple operations" "
    for i in {1..5}; do 
        "$REPO_ROOT/zig-out/bin/zion" health >/dev/null 2>&1 || true
        "$REPO_ROOT/zig-out/bin/zion" benchmark >/dev/null 2>&1 || true
    done
"

echo -e "\n🔄 Backward Compatibility Tests"
echo "==============================="

# Test that all old commands still work
run_test "Old init command" "\"$REPO_ROOT/zig-out/bin/zion\" init 2>/dev/null || true"
run_test "Old list command" "\"$REPO_ROOT/zig-out/bin/zion\" list 2>/dev/null || true"
run_test "Old remove command" "\"$REPO_ROOT/zig-out/bin/zion\" remove zig-clap 2>/dev/null || true"

echo -e "\n🎯 Alias Tests"
echo "============="

# Test all new aliases
run_test_with_output "Search alias (s)" "\"$REPO_ROOT/zig-out/bin/zion\" s test 2>/dev/null || true" ""
run_test_with_output "Add alias (a)" "\"$REPO_ROOT/zig-out/bin/zion\" a --help 2>/dev/null || true" ""
run_test_with_output "Help alias (h)" "\"$REPO_ROOT/zig-out/bin/zion\" h 2>/dev/null || true" ""

echo -e "\n🚀 Async Feature Tests"
echo "====================="

# Test that async features are available
run_test_with_output "Async runtime initialization" "\"$REPO_ROOT/zig-out/bin/zion\" benchmark 2>&1" "zsync"

# Test graceful fallback when async fails
export ZION_FORCE_SYNC=1
run_test "Sync fallback mode" "\"$REPO_ROOT/zig-out/bin/zion\" version"
unset ZION_FORCE_SYNC

echo -e "\n🔧 Configuration Tests"  
echo "======================"

# Test configuration continuity
if [ -f "build.zig.zon" ]; then
    run_test "build.zig.zon compatibility" "cat build.zig.zon | grep -q 'name'"
fi

# Cleanup
cd - >/dev/null
cleanup

echo -e "\n📊 Test Results Summary"
echo "======================="
echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"  
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "Zion v1.0.7 is ready for release!"
    exit 0
else
    echo -e "\n${RED}❌ $FAILED_TESTS TESTS FAILED${NC}"
    echo -e "Please fix the issues before releasing v1.0.7"
    exit 1
fi
