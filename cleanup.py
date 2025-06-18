import os
import shutil

# Remove test files
test_files = [
    '/data/projects/zion/compile_test.zig',
    '/data/projects/zion/test_search.zig', 
    '/data/projects/zion/test_simple.zig',
    '/data/projects/zion/test_build.sh',
    '/data/projects/zion/cleanup.py'
]

for file in test_files:
    try:
        if os.path.exists(file):
            os.remove(file)
            print(f"Removed {file}")
        else:
            print(f"File not found: {file}")
    except Exception as e:
        print(f"Error removing {file}: {e}")

# Check if nested test-project directory exists and clean it up
test_project_dir = '/data/projects/zion/test-project'
if os.path.exists(test_project_dir):
    try:
        shutil.rmtree(test_project_dir)
        print(f"Removed directory {test_project_dir}")
    except Exception as e:
        print(f"Error removing directory {test_project_dir}: {e}")

print("Cleanup complete")