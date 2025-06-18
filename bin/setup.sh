#!/bin/bash

# macOS Routing Manager - Setup Script
# Installs and configures the routing manager

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/usr/local/lib/wifi-daemon"
CONFIG_DIR="/etc/wifi-daemon"
DATA_DIR="/var/lib/wifi-daemon"
PLIST_FILE="/Library/LaunchDaemons/com.wifi-daemon.plist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    case "$level" in
        INFO) echo -e "${GREEN}[INFO]${NC} $*" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $*" ;;
        *) echo "[$level] $*" ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion)
    log "INFO" "macOS version: $macos_version"
    
    # Check required tools
    local required_tools=("jq" "networksetup" "route" "pfctl" "scutil")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        log "INFO" "Please install missing tools. For jq: brew install jq"
        exit 1
    fi
    
    log "INFO" "All required tools are available"
}

# Create directories
create_directories() {
    log "INFO" "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR/backups"
    mkdir -p "$DATA_DIR/logs"
    mkdir -p "$DATA_DIR/state"
    
    # Set permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$DATA_DIR"
    chmod 755 "$DATA_DIR/backups"
    chmod 755 "$DATA_DIR/logs"
    chmod 755 "$DATA_DIR/state"
    
    log "INFO" "Directories created successfully"
}

# Install scripts
install_scripts() {
    log "INFO" "Installing scripts..."
    
    # Copy all scripts
    cp "$PROJECT_DIR/bin/wifi-daemon" "$INSTALL_DIR/"
    cp "$PROJECT_DIR/bin/firewall-manager" "$INSTALL_DIR/"
    cp "$PROJECT_DIR/bin/route-manager" "$INSTALL_DIR/"
    cp "$PROJECT_DIR/bin/network-monitor" "$INSTALL_DIR/"
    cp "$PROJECT_DIR/bin/subnet-calculator.py" "$INSTALL_DIR/"
    
    # Set permissions
    chmod 755 "$INSTALL_DIR/wifi-daemon"
    chmod 755 "$INSTALL_DIR/firewall-manager"
    chmod 755 "$INSTALL_DIR/route-manager"
    chmod 755 "$INSTALL_DIR/network-monitor"
    chmod 755 "$INSTALL_DIR/subnet-calculator.py"
    
    # Create symlinks in /usr/local/bin for easy access
    ln -sf "$INSTALL_DIR/wifi-daemon" /usr/local/bin/wifi-daemon
    ln -sf "$INSTALL_DIR/network-monitor" /usr/local/bin/network-monitor
    
    log "INFO" "Scripts installed successfully"
}

# Install configuration
install_config() {
    log "INFO" "Installing configuration..."
    
    # Copy configuration files
    cp "$PROJECT_DIR/config/config.json" "$CONFIG_DIR/"
    cp "$PROJECT_DIR/config/prefixes.conf" "$CONFIG_DIR/"
    
    # Update paths in config.json to use system directories
    local temp_config=$(mktemp)
    jq --arg log_dir "$DATA_DIR/logs/wifi-daemon.log" \
       --arg backup_dir "$DATA_DIR/backups" \
       --arg prefixes_file "$CONFIG_DIR/prefixes.conf" \
       '.monitoring.log_file = $log_dir | .monitoring.backup_directory = $backup_dir | .prefixes.config_file = $prefixes_file' \
       "$CONFIG_DIR/config.json" > "$temp_config"
    
    mv "$temp_config" "$CONFIG_DIR/config.json"
    
    # Set permissions
    chmod 644 "$CONFIG_DIR/config.json"
    chmod 644 "$CONFIG_DIR/prefixes.conf"
    
    log "INFO" "Configuration installed successfully"
}

# Create LaunchDaemon plist
create_launchd_plist() {
    log "INFO" "Creating LaunchDaemon configuration..."
    
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wifi-daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/wifi-daemon</string>
        <string>daemon</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>StandardOutPath</key>
    <string>$DATA_DIR/logs/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$DATA_DIR/logs/daemon-error.log</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>UserName</key>
    <string>root</string>
</dict>
</plist>
EOF
    
    chmod 644 "$PLIST_FILE"
    log "INFO" "LaunchDaemon configuration created"
}

# Load LaunchDaemon
load_daemon() {
    log "INFO" "Loading LaunchDaemon..."
    
    if launchctl load "$PLIST_FILE"; then
        log "INFO" "LaunchDaemon loaded successfully"
    else
        log "WARN" "Failed to load LaunchDaemon - you can load it manually later"
    fi
}

# Unload LaunchDaemon
unload_daemon() {
    log "INFO" "Unloading LaunchDaemon..."
    
    if launchctl unload "$PLIST_FILE" 2>/dev/null; then
        log "INFO" "LaunchDaemon unloaded successfully"
    else
        log "INFO" "LaunchDaemon was not loaded"
    fi
}

# Uninstall function
uninstall() {
    log "INFO" "Uninstalling routing manager..."
    
    # Stop and unload daemon
    unload_daemon
    
    # Remove files
    rm -f "$PLIST_FILE"
    rm -f /usr/local/bin/wifi-daemon
    rm -f /usr/local/bin/network-monitor
    rm -rf "$INSTALL_DIR"
    
    # Optionally remove configuration and data
    read -p "Remove configuration and data directories? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -rf "$DATA_DIR"
        log "INFO" "Configuration and data directories removed"
    fi
    
    log "INFO" "Uninstall completed"
}

# Show status
show_status() {
    log "INFO" "Routing Manager Status"
    echo ""
    
    # Check if installed
    if [[ -f "$INSTALL_DIR/wifi-daemon" ]]; then
        echo "Installation: ✓ Installed"
    else
        echo "Installation: ✗ Not installed"
        return
    fi
    
    # Check daemon status
    if launchctl list | grep -q "com.wifi-daemon"; then
        echo "Daemon: ✓ Loaded"
    else
        echo "Daemon: ✗ Not loaded"
    fi
    
    # Check if running
    if pgrep -f "wifi-daemon.*daemon" >/dev/null; then
        echo "Process: ✓ Running"
    else
        echo "Process: ✗ Not running"
    fi
    
    # Check configuration
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
        echo "Configuration: ✓ Present"
        local target_ssid
        target_ssid=$(jq -r '.target_ssid' "$CONFIG_DIR/config.json" 2>/dev/null || echo "Unknown")
        echo "Target SSID: $target_ssid"
    else
        echo "Configuration: ✗ Missing"
    fi
}

# Test installation
test_installation() {
    log "INFO" "Testing installation..."
    
    # Test script execution
    if "$INSTALL_DIR/wifi-daemon" status >/dev/null 2>&1; then
        log "INFO" "✓ Main script executable"
    else
        log "ERROR" "✗ Main script not executable"
    fi
    
    # Test network monitor
    if "$INSTALL_DIR/network-monitor" interface >/dev/null 2>&1; then
        log "INFO" "✓ Network monitor working"
    else
        log "ERROR" "✗ Network monitor not working"
    fi
    
    # Test configuration
    if jq . "$CONFIG_DIR/config.json" >/dev/null 2>&1; then
        log "INFO" "✓ Configuration file valid"
    else
        log "ERROR" "✗ Configuration file invalid"
    fi
    
    log "INFO" "Test completed"
}

# Main execution
main() {
    local action="${1:-install}"
    
    case "$action" in
        install)
            log "INFO" "Installing macOS Routing Manager..."
            check_root
            check_requirements
            create_directories
            install_scripts
            install_config
            create_launchd_plist
            load_daemon
            test_installation
            log "INFO" "Installation completed successfully!"
            echo ""
            log "INFO" "Use 'wifi-daemon status' to check current state"
            log "INFO" "Use 'launchctl unload $PLIST_FILE' to stop the daemon"
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        status)
            show_status
            ;;
        test)
            test_installation
            ;;
        reload)
            check_root
            unload_daemon
            load_daemon
            ;;
        *)
            echo "Usage: $0 {install|uninstall|status|test|reload}"
            echo ""
            echo "Actions:"
            echo "  install   - Install routing manager (requires sudo)"
            echo "  uninstall - Uninstall routing manager (requires sudo)"
            echo "  status    - Show installation status"
            echo "  test      - Test installation"
            echo "  reload    - Reload daemon (requires sudo)"
            exit 1
            ;;
    esac
}

main "$@"