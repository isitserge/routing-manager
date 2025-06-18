# macOS Routing Manager - Installation Validation Guide

This guide provides comprehensive steps to validate your macOS routing manager installation and troubleshoot common issues.

## Prerequisites

Before validating the installation, ensure you have:
- macOS 10.15 (Catalina) or later
- Administrative (sudo) access
- Required system tools: `networksetup`, `route`, `pfctl`, `scutil`, `jq`

## Step 1: Run Pre-Installation Tests

Before installing, validate the system configuration:

```bash
./bin/test-routing.sh
```

This comprehensive test suite checks:
- Configuration file validity
- Script executability and syntax
- System requirements
- Network interface detection
- Firewall rule generation
- Routing functionality
- Logging capabilities

All tests should pass before proceeding with installation.

## Step 2: Check System Status

Run the status script to get a complete overview:

```bash
./bin/status.sh
```

This shows:
- System requirements status
- Configuration validity
- Installation state
- Network connection status
- Running processes

## Step 3: Installation

### Standard Installation

```bash
sudo ./bin/setup.sh install
```

### Common Installation Issues

#### Issue: "Main script not executable"

This error occurs due to a circular symlink bug in the installation script. To fix:

1. Remove the broken symlink:
   ```bash
   sudo rm -f /usr/local/bin/wifi-daemon
   ```

2. Manually install the daemon:
   ```bash
   sudo mkdir -p /usr/local/lib/wifi-daemon
   sudo cp bin/wifi-daemon /usr/local/lib/wifi-daemon/
   sudo chmod +x /usr/local/lib/wifi-daemon/wifi-daemon
   sudo ln -sf /usr/local/lib/wifi-daemon/wifi-daemon /usr/local/bin/wifi-daemon
   ```

3. Complete the installation:
   ```bash
   sudo ./bin/setup.sh install
   ```

## Step 4: Post-Installation Validation

### 1. Verify File Installation

Check that all files are properly installed:

```bash
# Check main daemon directory
ls -la /usr/local/lib/wifi-daemon/

# Check symlinks
ls -la /usr/local/bin/wifi-daemon
ls -la /usr/local/bin/network-monitor

# Check configuration
ls -la /etc/wifi-daemon/

# Check data directory
ls -la /var/lib/wifi-daemon/

# Check LaunchDaemon
ls -la /Library/LaunchDaemons/com.wifi.daemon.plist
```

### 2. Verify LaunchDaemon

Check if the daemon is loaded:

```bash
sudo launchctl list | grep com.wifi.daemon
```

Check daemon status:

```bash
sudo launchctl print system/com.wifi.daemon
```

### 3. Run Post-Installation Tests

After installation, run the test suite with sudo:

```bash
sudo ./bin/test-routing.sh
```

All tests should pass, including permission-related tests.

### 4. Check Logs

Monitor the daemon logs:

```bash
# Real-time log monitoring
tail -f /var/log/wifi-daemon.log

# Check for errors
grep ERROR /var/log/wifi-daemon.log
```

### 5. Test Network Switching

1. Connect to your target SSID (as configured in config.json)
2. Verify routes are applied:
   ```bash
   netstat -rn | grep -E "192.168|10.0|172.16"
   ```

3. Check firewall rules:
   ```bash
   sudo pfctl -sr | grep -E "pass|block"
   ```

## Step 5: Manual Operation Testing

Test individual components:

### Network Monitoring
```bash
# Check current WiFi status
./bin/network-monitor status

# Get WiFi interface
./bin/network-monitor interface

# Get current SSID
./bin/network-monitor ssid
```

### Route Management
```bash
# View current routes
./bin/route-manager show

# Backup routes (dry-run)
./bin/route-manager backup /tmp/route-backup.txt
```

### Firewall Management
```bash
# Generate firewall rules (dry-run)
./bin/firewall-manager generate en0
```

## Troubleshooting

### Service Won't Start

1. Check LaunchDaemon syntax:
   ```bash
   plutil -lint /Library/LaunchDaemons/com.wifi.daemon.plist
   ```

2. Check permissions:
   ```bash
   ls -la /usr/local/lib/wifi-daemon/wifi-daemon
   # Should be executable (-rwxr-xr-x)
   ```

3. Try manual start:
   ```bash
   sudo /usr/local/lib/wifi-daemon/wifi-daemon
   ```

### Routes Not Applied

1. Verify WiFi connection:
   ```bash
   ./bin/network-monitor status
   ```

2. Check if SSID matches configuration:
   ```bash
   ./bin/network-monitor ssid
   grep target_ssid /etc/wifi-daemon/config.json
   ```

3. Review logs for errors:
   ```bash
   tail -50 /var/log/wifi-daemon.log | grep -E "ERROR|WARN"
   ```

### Firewall Rules Not Working

1. Check pfctl status:
   ```bash
   sudo pfctl -s info
   ```

2. Verify rule file exists:
   ```bash
   ls -la /etc/wifi-daemon/pf-wifi.conf
   ```

3. Test rule syntax:
   ```bash
   sudo pfctl -n -f /etc/wifi-daemon/pf-wifi.conf
   ```

## Uninstallation

To completely remove the routing manager:

```bash
sudo ./bin/setup.sh uninstall
```

Verify removal:
```bash
# Should return no results
ls /usr/local/bin/wifi-daemon 2>/dev/null
ls /etc/wifi-daemon 2>/dev/null
ls /var/lib/wifi-daemon 2>/dev/null
sudo launchctl list | grep com.wifi.daemon
```

## Summary

A properly validated installation should show:
- ✅ All tests passing in `test-routing.sh`
- ✅ Daemon loaded in launchctl
- ✅ Configuration files in `/etc/wifi-daemon/`
- ✅ Executable scripts in `/usr/local/lib/wifi-daemon/`
- ✅ Symlinks in `/usr/local/bin/` for easy access
- ✅ Active log file in `/var/log/wifi-daemon.log`
- ✅ Routes applied when connected to target SSID
- ✅ Firewall rules active when on target network

For additional support, check the logs and run the diagnostic scripts in debug mode by adding `set -x` to the script headers.