#!/bin/bash
# setup.sh - Test environment setup

set -euo pipefail

# Test environment paths
# Use BASH_SOURCE for correct path when sourced
_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_DIR="$(dirname "$_SETUP_DIR")"
TEST_ROOT="${TEST_ROOT:-$_PROJECT_DIR/test-env}"
export TEST_HOME="$TEST_ROOT/home"
export SCRIPT_DIR="$_PROJECT_DIR"
export OMARCHY_SYNC="$SCRIPT_DIR/omarchy-sync.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Clean up test environment
cleanup_test_env() {
    rm -rf "$TEST_ROOT"
}

# Create fresh test environment
create_test_env() {
    cleanup_test_env

    mkdir -p "$TEST_HOME/.config/small-app"
    mkdir -p "$TEST_HOME/.config/large-app"
    mkdir -p "$TEST_HOME/.config/nested/with/.git"
    mkdir -p "$TEST_HOME/.local/share/applications"
    mkdir -p "$TEST_HOME/.local/bin"

    # Configure git to not require GPG signing in test environment
    cat > "$TEST_HOME/.gitconfig" << 'GITCONFIG'
[user]
    name = Test User
    email = test@example.com
[commit]
    gpgsign = false
[tag]
    gpgsign = false
GITCONFIG

    # Create test files
    echo "small config content" > "$TEST_HOME/.config/small-app/config.txt"
    echo "another small file" > "$TEST_HOME/.config/small-app/settings.json"

    # Create large file (25MB, over default 20MB threshold)
    dd if=/dev/zero of="$TEST_HOME/.config/large-app/bigfile" bs=1M count=25 2>/dev/null
    echo "large app config" > "$TEST_HOME/.config/large-app/config.txt"

    # Create nested config with .git directory
    echo "nested config" > "$TEST_HOME/.config/nested/with/config.txt"
    echo "git HEAD ref" > "$TEST_HOME/.config/nested/with/.git/HEAD"

    # Create local share and bin files
    cat > "$TEST_HOME/.local/share/applications/test.desktop" << 'EOF'
[Desktop Entry]
Name=Test App
Exec=/usr/bin/test-app
Type=Application
EOF

    cat > "$TEST_HOME/.local/bin/test-script" << 'EOF'
#!/bin/bash
echo "Hello from test script"
EOF
    chmod +x "$TEST_HOME/.local/bin/test-script"
}

# Run omarchy-sync with test home
run_omarchy() {
    "$OMARCHY_SYNC" --test "$TEST_HOME" "$@"
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist: $file}"
    if [[ -f "$file" ]]; then
        return 0
    else
        log_fail "$msg"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local msg="${2:-Directory should exist: $dir}"
    if [[ -d "$dir" ]]; then
        return 0
    else
        log_fail "$msg"
        return 1
    fi
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local msg="${3:-File $file should contain: $pattern}"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        log_fail "$msg"
        return 1
    fi
}

# Assert file does not exist
assert_file_not_exists() {
    local file="$1"
    local msg="${2:-File should not exist: $file}"
    if [[ ! -f "$file" ]]; then
        return 0
    else
        log_fail "$msg"
        return 1
    fi
}

# Get backup path
get_backup_path() {
    echo "$TEST_HOME/.local/share/omarchy-sync/backup"
}

# Get config path
get_config_path() {
    echo "$TEST_HOME/.config/omarchy-sync/config.toml"
}
