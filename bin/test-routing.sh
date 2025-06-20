#!/bin/bash

# macOS Routing Manager - Test Script
# Tests the routing configuration without permanent changes

set -euo pipefail

# Configuration
# Resolve symlinks to get the actual script directory
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Check if running from installed location
if [[ "$SCRIPT_DIR" == "/usr/local/lib/wifi-daemon" ]]; then
    # Installed mode - use system paths
    CONFIG_DIR="/etc/wifi-daemon"
    LOG_DIR="/var/lib/wifi-daemon/logs"
else
    # Development mode - use project paths
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    CONFIG_DIR="${PROJECT_DIR}/config"
    LOG_DIR="${PROJECT_DIR}/logs"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Logging function
log() {
    local level="$1"
    shift
    case "$level" in
        PASS) echo -e "${GREEN}[PASS]${NC} $*"; TESTS_PASSED=$((TESTS_PASSED + 1)) ;;
        FAIL) echo -e "${RED}[FAIL]${NC} $*"; TESTS_FAILED=$((TESTS_FAILED + 1)) ;;
        INFO) echo -e "${BLUE}[INFO]${NC} $*" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $*" ;;
        *) echo "[$level] $*" ;;
    esac
}

# Test configuration file
test_config() {
    log "INFO" "Testing configuration..."
    
    # Check if running from installed location
    if [[ -f "/etc/wifi-daemon/config.json" ]]; then
        # Installed mode
        local config_file="/etc/wifi-daemon/config.json"
        local prefixes_file="/etc/wifi-daemon/prefixes.conf"
    else
        # Development mode
        local config_file="${CONFIG_DIR}/config.json"
        local prefixes_file="${CONFIG_DIR}/prefixes.conf"
    fi
    
    # Test config.json
    if [[ -f "$config_file" ]]; then
        if jq . "$config_file" >/dev/null 2>&1; then
            log "PASS" "Configuration file is valid JSON"
        else
            log "FAIL" "Configuration file is not valid JSON"
        fi
        
        # Test required fields
        local required_fields=("target_ssid" "wifi_interface" "security_layers" "prefixes")
        for field in "${required_fields[@]}"; do
            if jq -e ".$field" "$config_file" >/dev/null 2>&1; then
                log "PASS" "Required field '$field' present in config"
            else
                log "FAIL" "Required field '$field' missing from config"
            fi
        done
    else
        log "FAIL" "Configuration file not found: $config_file"
    fi
    
    # Test prefixes.conf
    if [[ -f "$prefixes_file" ]]; then
        log "PASS" "Prefixes file exists"
        
        # Check for valid network prefixes
        local prefix_count=0
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            if [[ "$line" =~ ^!?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                ((prefix_count++))
            fi
        done < "$prefixes_file"
        
        if [[ $prefix_count -gt 0 ]]; then
            log "PASS" "Found $prefix_count valid network prefixes"
        else
            log "FAIL" "No valid network prefixes found"
        fi
    else
        log "FAIL" "Prefixes file not found: $prefixes_file"
    fi
}

# Test script permissions and executability
test_scripts() {
    log "INFO" "Testing scripts..."
    
    local scripts=("wifi-daemon" "firewall-manager" "route-manager" "network-monitor")
    
    for script in "${scripts[@]}"; do
        local script_path="${PROJECT_DIR}/bin/$script"
        
        if [[ -f "$script_path" ]]; then
            if [[ -x "$script_path" ]]; then
                log "PASS" "Script $script is executable"
            else
                log "FAIL" "Script $script is not executable"
            fi
            
            # Test basic syntax
            if bash -n "$script_path" 2>/dev/null; then
                log "PASS" "Script $script has valid bash syntax"
            else
                log "FAIL" "Script $script has syntax errors"
            fi
        else
            log "FAIL" "Script $script not found"
        fi
    done
}

# Test system requirements
test_requirements() {
    log "INFO" "Testing system requirements..."
    
    # Test required commands
    local required_commands=("networksetup" "route" "pfctl" "scutil" "jq")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log "PASS" "Command '$cmd' is available"
        else
            log "FAIL" "Command '$cmd' is not available"
        fi
    done
    
    # Test if running on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        log "PASS" "Running on macOS"
    else
        log "FAIL" "Not running on macOS (detected: $(uname))"
    fi
    
    # Test macOS version
    local macos_version
    if macos_version=$(sw_vers -productVersion 2>/dev/null); then
        log "PASS" "macOS version: $macos_version"
    else
        log "FAIL" "Could not determine macOS version"
    fi
}

# Test network interface detection
test_network_interface() {
    log "INFO" "Testing network interface detection..."
    
    # Test WiFi interface detection
    if "$PROJECT_DIR/bin/network-monitor" interface >/dev/null 2>&1; then
        local wifi_output wifi_interface
        wifi_output=$("$PROJECT_DIR/bin/network-monitor" interface)
        # Extract just the interface name (e.g., en0) from "WiFi Interface: en0"
        wifi_interface=$(echo "$wifi_output" | awk -F': ' '{print $2}')
        log "PASS" "WiFi interface detected: $wifi_interface"
        
        # Test if interface exists
        if ifconfig "$wifi_interface" >/dev/null 2>&1; then
            log "PASS" "WiFi interface $wifi_interface exists"
        else
            log "FAIL" "WiFi interface $wifi_interface does not exist"
        fi
    else
        log "FAIL" "Could not detect WiFi interface"
    fi
}

# Test firewall rule generation
test_firewall_rules() {
    log "INFO" "Testing firewall rule generation..."
    
    local test_interface="en1"  # Common WiFi interface
    # Check if running from installed location
    if [[ -f "/etc/wifi-daemon/prefixes.conf" ]]; then
        local prefixes_file="/etc/wifi-daemon/prefixes.conf"
    else
        local prefixes_file="${CONFIG_DIR}/prefixes.conf"
    fi
    
    # Test rule generation
    if "${SCRIPT_DIR}/firewall-manager" generate "$test_interface" "$prefixes_file" 2>/dev/null; then
        log "PASS" "Firewall rule generation succeeded"
        
        # Check if generated file exists and has content
        local pf_file="${CONFIG_DIR}/pf-wifi.conf"
        if [[ -f "$pf_file" && -s "$pf_file" ]]; then
            log "PASS" "Firewall rules file generated with content"
            
            # Test rule syntax
            if pfctl -nf "$pf_file" 2>/dev/null; then
                log "PASS" "Generated firewall rules have valid syntax"
            else
                log "FAIL" "Generated firewall rules have syntax errors"
            fi
        else
            log "FAIL" "Firewall rules file not generated or empty"
        fi
    else
        log "FAIL" "Firewall rule generation failed"
    fi
}

# Test routing functionality
test_routing() {
    log "INFO" "Testing routing functionality..."
    
    # Test route backup
    if "$PROJECT_DIR/bin/route-manager" backup >/dev/null 2>&1; then
        log "PASS" "Route backup functionality works"
    else
        log "FAIL" "Route backup functionality failed"
    fi
    
    # Test default route detection
    if route -n get default >/dev/null 2>&1; then
        log "PASS" "Default route is accessible"
        
        local default_info
        default_info=$(route -n get default | grep -E "(gateway|interface)" | head -2)
        if [[ -n "$default_info" ]]; then
            log "PASS" "Default route information available"
        else
            log "FAIL" "Could not get default route information"
        fi
    else
        log "FAIL" "No default route found"
    fi
}

# Test log directory creation
test_logging() {
    log "INFO" "Testing logging functionality..."
    
    local log_dir="${PROJECT_DIR}/logs"
    mkdir -p "$log_dir"
    
    # Test log file creation
    local test_log="${log_dir}/test.log"
    if echo "Test log entry" > "$test_log" 2>/dev/null; then
        log "PASS" "Log file creation works"
        rm -f "$test_log"
    else
        log "FAIL" "Log file creation failed"
    fi
}

# Test permissions (if running as root)
test_permissions() {
    log "INFO" "Testing permissions..."
    
    if [[ $EUID -eq 0 ]]; then
        log "PASS" "Running as root - all operations should be permitted"
        
        # Test pfctl access
        if pfctl -s info >/dev/null 2>&1; then
            log "PASS" "pfctl is accessible"
        else
            log "WARN" "pfctl access failed - may need to enable"
        fi
        
        # Test route modification capability
        if route -n get default >/dev/null 2>&1; then
            log "PASS" "Route table access available"
        else
            log "FAIL" "Route table access failed"
        fi
    else
        log "WARN" "Not running as root - some operations may fail during actual usage"
    fi
}

# Run all tests
run_all_tests() {
    echo "=== macOS Routing Manager Test Suite ==="
    echo ""
    
    test_config
    echo ""
    
    test_scripts
    echo ""
    
    test_requirements
    echo ""
    
    test_network_interface
    echo ""
    
    test_firewall_rules
    echo ""
    
    test_routing
    echo ""
    
    test_logging
    echo ""
    
    test_permissions
    echo ""
    
    # Summary
    echo "=== Test Summary ==="
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! The system is ready for deployment.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review the issues above.${NC}"
        exit 1
    fi
}

# Cleanup test files
cleanup() {
    log "INFO" "Cleaning up test files..."
    rm -f "${CONFIG_DIR}/pf-wifi.conf" 2>/dev/null || true
    rm -f "${LOG_DIR}/test.log" 2>/dev/null || true
}

# Main execution
main() {
    local action="${1:-all}"
    
    case "$action" in
        all)
            run_all_tests
            ;;
        config)
            test_config
            ;;
        scripts)
            test_scripts
            ;;
        requirements)
            test_requirements
            ;;
        network)
            test_network_interface
            ;;
        firewall)
            test_firewall_rules
            ;;
        routing)
            test_routing
            ;;
        permissions)
            test_permissions
            ;;
        cleanup)
            cleanup
            ;;
        *)
            echo "Usage: $0 {all|config|scripts|requirements|network|firewall|routing|permissions|cleanup}"
            echo ""
            echo "Test categories:"
            echo "  all          - Run all tests"
            echo "  config       - Test configuration files"
            echo "  scripts      - Test script syntax and permissions"
            echo "  requirements - Test system requirements"
            echo "  network      - Test network interface detection"
            echo "  firewall     - Test firewall rule generation"
            echo "  routing      - Test routing functionality"
            echo "  permissions  - Test required permissions"
            echo "  cleanup      - Clean up test files"
            exit 1
            ;;
    esac
}

# Cleanup on exit
trap cleanup EXIT

main "$@"