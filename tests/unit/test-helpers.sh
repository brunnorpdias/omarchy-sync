#!/bin/bash
# test-helpers.sh - Unit tests for lib/helpers.sh

# Test: log outputs with [*] prefix
test_log_output() {
    local result
    result=$(log "test message" 2>&1)
    assert_eq "[*] test message" "$result" "log should output with [*] prefix"
}
run_test "log outputs with [*] prefix" test_log_output

# Test: error outputs with [ERROR] prefix to stderr
test_error_output() {
    local result
    result=$(error "test error" 2>&1)
    assert_eq "[ERROR] test error" "$result" "error should output with [ERROR] prefix"
}
run_test "error outputs with [ERROR] prefix" test_error_output

# Test: done_ outputs with [DONE] prefix
test_done_output() {
    local result
    result=$(done_ "test done" 2>&1)
    assert_eq "[DONE] test done" "$result" "done_ should output with [DONE] prefix"
}
run_test "done_ outputs with [DONE] prefix" test_done_output

# Test: warn outputs with [WARN] prefix
test_warn_output() {
    local result
    result=$(warn "test warning" 2>&1)
    assert_eq "[WARN] test warning" "$result" "warn should output with [WARN] prefix"
}
run_test "warn outputs with [WARN] prefix" test_warn_output

# Test: init_logging creates log directory
test_init_logging_creates_dir() {
    local log_dir="$TEST_HOME/.local/share/omarchy-sync"
    rm -rf "$log_dir"
    init_logging "$log_dir/test.log"
    assert_true "[[ -d \"$log_dir\" ]]" "init_logging should create log directory"
}
run_test "init_logging creates log directory" test_init_logging_creates_dir

# Test: init_logging creates log file with session header
test_init_logging_creates_file() {
    local log_file="$TEST_HOME/.local/share/omarchy-sync/test.log"
    rm -f "$log_file"
    init_logging "$log_file"
    assert_true "[[ -f \"$log_file\" ]]" "init_logging should create log file"
    assert_true "grep -q 'Session started' \"$log_file\"" "Log should contain session header"
}
run_test "init_logging creates log file with session header" test_init_logging_creates_file

# Test: log_write writes to log file when enabled
test_log_write_enabled() {
    local log_file="$TEST_HOME/.local/share/omarchy-sync/test.log"
    rm -f "$log_file"
    init_logging "$log_file"
    log_write "INFO" "test log message"
    assert_true "grep -q 'test log message' \"$log_file\"" "log_write should write to file"
    assert_true "grep -q '\\[INFO\\]' \"$log_file\"" "log_write should include level"
}
run_test "log_write writes to log file when enabled" test_log_write_enabled

# Test: log_write does nothing when disabled
test_log_write_disabled() {
    LOG_ENABLED=false
    local log_file="$TEST_HOME/.local/share/omarchy-sync/disabled.log"
    rm -f "$log_file"
    log_write "INFO" "should not appear"
    assert_true "[[ ! -f \"$log_file\" ]]" "log_write should not create file when disabled"
}
run_test "log_write does nothing when disabled" test_log_write_disabled

# Test: register_mount adds device to array
test_register_mount() {
    _MOUNTED_DEVICES=()
    register_mount "/dev/sdb1"
    assert_eq "/dev/sdb1" "${_MOUNTED_DEVICES[0]}" "register_mount should add device"
}
run_test "register_mount adds device to array" test_register_mount

# Test: unregister_mount removes device from array
test_unregister_mount() {
    _MOUNTED_DEVICES=("/dev/sdb1" "/dev/sdc1")
    unregister_mount "/dev/sdb1"
    assert_eq "1" "${#_MOUNTED_DEVICES[@]}" "unregister_mount should remove device"
    assert_eq "/dev/sdc1" "${_MOUNTED_DEVICES[0]}" "Remaining device should be sdc1"
}
run_test "unregister_mount removes device from array" test_unregister_mount

# Test: run_or_fail returns success on successful command
test_run_or_fail_success() {
    local result
    if run_or_fail "test" true; then
        result="success"
    else
        result="failure"
    fi
    assert_eq "success" "$result" "run_or_fail should return success on successful command"
}
run_test "run_or_fail returns success on successful command" test_run_or_fail_success

# Test: run_or_fail returns failure on failed command
test_run_or_fail_failure() {
    local result
    if run_or_fail "test" false 2>/dev/null; then
        result="success"
    else
        result="failure"
    fi
    assert_eq "failure" "$result" "run_or_fail should return failure on failed command"
}
run_test "run_or_fail returns failure on failed command" test_run_or_fail_failure

# Test: check_dependencies doesn't fail with required commands
test_check_dependencies() {
    # This should not exit since all commands are typically available
    local result
    if (check_dependencies 2>/dev/null); then
        result="success"
    else
        result="failure"
    fi
    assert_eq "success" "$result" "check_dependencies should pass when all commands exist"
}
run_test "check_dependencies passes when all commands exist" test_check_dependencies
