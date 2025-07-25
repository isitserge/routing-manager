#!/bin/bash

# macOS Routing Manager - Status Script
# Shows comprehensive system status

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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Status indicators
OK="✓"
FAIL="✗"
WARN="!"

# Print header
print_header() {
    echo -e "${CYAN}=== macOS Routing Manager Status ===${NC}"
    echo "Timestamp: $(date)"
    echo ""
}

# Check installation status
check_installation() {
    echo -e "${BLUE}Installation Status:${NC}"
    
    if [[ -f "/usr/local/bin/wifi-daemon/wifi-daemon" ]]; then
        echo -e "  ${GREEN}${OK}${NC} System installed"
        
        # Check daemon status
        if launchctl list | grep -q "com.wifi-daemon"; then
            echo -e "  ${GREEN}${OK}${NC} Daemon loaded"
        else
            echo -e "  ${YELLOW}${WARN}${NC} Daemon not loaded"
        fi
        
        # Check if running
        if pgrep -f "wifi-daemon.*daemon" >/dev/null; then
            echo -e "  ${GREEN}${OK}${NC} Process running"
        else
            echo -e "  ${YELLOW}${WARN}${NC} Process not running"
        fi
    else
        echo -e "  ${YELLOW}${WARN}${NC} System not installed (development mode)"
    fi
    echo ""
}

# Check configuration
check_configuration() {
    echo -e "${BLUE}Configuration:${NC}"
    
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
    
    # Check config files
    if [[ -f "$config_file" ]]; then
        echo -e "  ${GREEN}${OK}${NC} Main config present"
        
        # Show key settings
        local target_ssid
        local wifi_interface
        local use_firewall
        local use_routing
        
        target_ssid=$(jq -r '.target_ssid' "$config_file" 2>/dev/null || echo "Unknown")
        wifi_interface=$(jq -r '.wifi_interface' "$config_file" 2>/dev/null || echo "Unknown")
        use_firewall=$(jq -r '.security_layers.firewall' "$config_file" 2>/dev/null || echo "Unknown")
        use_routing=$(jq -r '.security_layers.routing' "$config_file" 2>/dev/null || echo "Unknown")
        
        echo "    Target SSID: $target_ssid"
        echo "    WiFi Interface: $wifi_interface"
        echo "    Use Firewall: $use_firewall"
        echo "    Use Routing: $use_routing"
    else
        echo -e "  ${RED}${FAIL}${NC} Main config missing"
    fi
    
    if [[ -f "$prefixes_file" ]]; then
        echo -e "  ${GREEN}${OK}${NC} Prefixes config present"
        
        # Count prefixes
        local include_count=0
        local exclude_count=0
        
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            if [[ "$line" =~ ^! ]]; then
                ((exclude_count++))
            else
                ((include_count++))
            fi
        done < "$prefixes_file"
        
        echo "    Include prefixes: $include_count"
        echo "    Exclude prefixes: $exclude_count"
    else
        echo -e "  ${RED}${FAIL}${NC} Prefixes config missing"
    fi
    echo ""
}

# Check network status
check_network() {
    echo -e "${BLUE}Network Status:${NC}"
    
    # Get WiFi interface
    local wifi_interface
    if command -v "$PROJECT_DIR/bin/network-monitor" >/dev/null 2>&1; then
        wifi_interface=$("$PROJECT_DIR/bin/network-monitor" interface 2>/dev/null || echo "Unknown")
    else
        wifi_interface=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device:" | awk '{print $2}' | head -n 1 || echo "Unknown")
    fi
    
    echo "  WiFi Interface: $wifi_interface"
    
    if [[ "$wifi_interface" != "Unknown" ]] && ifconfig "$wifi_interface" >/dev/null 2>&1; then
        echo -e "  ${GREEN}${OK}${NC} WiFi interface exists"
        
        # Get current SSID
        local current_ssid
        # NOTE: networksetup -getairportnetwork is broken and unreliable - DO NOT USE
        current_ssid=$(system_profiler SPAirPortDataType 2>/dev/null | grep -A 2 "Current Network Information:" | grep -v "Current Network Information:" | grep ":" | head -1 | sed 's/://g' | sed 's/^[[:space:]]*//' || echo "Not connected")
        echo "  Current SSID: $current_ssid"
        
        # Get WiFi IP
        local wifi_ip
        wifi_ip=$(ifconfig "$wifi_interface" | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' || echo "No IP")
        echo "  WiFi IP: $wifi_ip"
        
        # Check if connected to target
        local target_ssid
        # Use the same config file detection
        local config_path
        if [[ -f "/etc/wifi-daemon/config.json" ]]; then
            config_path="/etc/wifi-daemon/config.json"
        else
            config_path="${CONFIG_DIR}/config.json"
        fi
        target_ssid=$(jq -r '.target_ssid' "$config_path" 2>/dev/null || echo "SOME-SSID")
        
        if [[ "$current_ssid" == "$target_ssid" ]]; then
            echo -e "  ${GREEN}${OK}${NC} Connected to target SSID"
        else
            echo -e "  ${YELLOW}${WARN}${NC} Not connected to target SSID ($target_ssid)"
        fi
    else
        echo -e "  ${RED}${FAIL}${NC} WiFi interface not available"
    fi
    echo ""
}

# Check routing status
check_routing() {
    echo -e "${BLUE}Routing Status:${NC}"
    
    # Check default route
    if route -n get default >/dev/null 2>&1; then
        local default_interface
        local default_gateway
        
        default_interface=$(route -n get default | grep interface | awk '{print $2}' || echo "Unknown")
        default_gateway=$(route -n get default | grep gateway | awk '{print $2}' || echo "Unknown")
        
        echo "  Default route: $default_gateway via $default_interface"
        
        # Check if default is via WiFi (should NOT be)
        local wifi_interface
        wifi_interface=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device:" | awk '{print $2}' | head -n 1 || echo "Unknown")
        
        if [[ "$default_interface" == "$wifi_interface" ]]; then
            echo -e "  ${RED}${FAIL}${NC} WARNING: Default route is via WiFi!"
        else
            echo -e "  ${GREEN}${OK}${NC} Default route is NOT via WiFi"
        fi
        
        # Count WiFi routes
        if [[ "$wifi_interface" != "Unknown" ]]; then
            local wifi_route_count
            wifi_route_count=$(netstat -rn | grep -c "$wifi_interface" || echo "0")
            echo "  WiFi routes: $wifi_route_count"
        fi
    else
        echo -e "  ${RED}${FAIL}${NC} No default route found"
    fi
    echo ""
}

# Check firewall status
check_firewall() {
    echo -e "${BLUE}Firewall Status:${NC}"
    
    # Check if pfctl is available
    if command -v pfctl >/dev/null 2>&1; then
        echo -e "  ${GREEN}${OK}${NC} pfctl available"
        
        # Check if enabled (requires root)
        if pfctl -s info >/dev/null 2>&1; then
            if pfctl -s info | grep -q "Status: Enabled"; then
                echo -e "  ${GREEN}${OK}${NC} Packet filtering enabled"
            else
                echo -e "  ${YELLOW}${WARN}${NC} Packet filtering disabled"
            fi
            
            # Check for WiFi rules
            local wifi_interface
            wifi_interface=$(networksetup -listallhardwareports | grep -A 1 "Wi-Fi" | grep "Device:" | awk '{print $2}' | head -n 1 || echo "Unknown")
            
            if [[ "$wifi_interface" != "Unknown" ]]; then
                local wifi_rule_count
                wifi_rule_count=$(pfctl -s rules 2>/dev/null | grep -c "$wifi_interface" || echo "0")
                echo "  WiFi firewall rules: $wifi_rule_count"
            fi
        else
            echo -e "  ${YELLOW}${WARN}${NC} Cannot access pfctl (may need root privileges)"
        fi
    else
        echo -e "  ${RED}${FAIL}${NC} pfctl not available"
    fi
    echo ""
}

# Check system requirements
check_requirements() {
    echo -e "${BLUE}System Requirements:${NC}"
    
    local required_tools=("jq" "networksetup" "route" "pfctl" "scutil")
    local all_present=true
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ${GREEN}${OK}${NC} $tool"
        else
            echo -e "  ${RED}${FAIL}${NC} $tool (missing)"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == "true" ]]; then
        echo -e "  ${GREEN}${OK}${NC} All required tools present"
    else
        echo -e "  ${RED}${FAIL}${NC} Some required tools missing"
    fi
    echo ""
}

# Show log tail
show_recent_logs() {
    echo -e "${BLUE}Recent Log Entries:${NC}"
    
    local log_file="${PROJECT_DIR}/logs/wifi-daemon.log"
    
    if [[ -f "$log_file" ]]; then
        echo "  Last 5 entries from $log_file:"
        tail -5 "$log_file" | sed 's/^/    /'
    else
        echo "  No log file found at $log_file"
    fi
    echo ""
}

# Main execution
main() {
    print_header
    check_installation
    check_configuration
    check_network
    check_routing
    check_firewall
    check_requirements
    show_recent_logs
    
    echo -e "${CYAN}Use './bin/test-routing.sh' for comprehensive testing${NC}"
    echo -e "${CYAN}Use 'wifi-daemon status' for runtime status${NC}"
}

main "$@"