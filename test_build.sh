#!/bin/bash
cd /data/projects/zion
echo "Current directory: $(pwd)"
echo "Listing files:"
ls -la
echo "Running zig build:"
zig build
echo "Build exit code: $?"