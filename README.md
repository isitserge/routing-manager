# macOS Routing Manager

A comprehensive macOS routing management solution that monitors WiFi connections and automatically manages routing tables with dual-layer security to ensure zero traffic leakage.

## Overview

This solution provides bulletproof traffic isolation for specific WiFi networks by using both firewall rules (`pfctl`) and route table manipulation. When connected to a target WiFi network (SOME-SSID), it:

- **Prevents default route through WiFi** - Ensures WiFi never becomes the default route
- **Configurable prefix routing** - Only specified network prefixes route through WiFi
- **Dual-layer security** - Firewall + routing for zero traffic leakage
- **Automatic monitoring** - Continuously monitors WiFi connection state
- **Safe rollback** - Automatic cleanup on disconnection

## Features

- ✅ **Zero Traffic Leakage** - Dual-layer protection (firewall + routing)
- ✅ **Automatic Detection** - Monitors for specific SSID connections
- ✅ **Configurable Prefixes** - File-based network prefix configuration
- ✅ **Safe Operation** - Preserves original routing, automatic rollback
- ✅ **System Integration** - LaunchDaemon for automatic startup
- ✅ **Comprehensive Logging** - Detailed operation logging
- ✅ **Test Suite** - Built-in testing and validation

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   scutil        │    │  Firewall Layer  │    │  Route Layer    │
│   Monitor       │───▶│  (pfctl rules)   │───▶│  (route table)  │
│                 │    │                  │    │                 │
│ SOME-SSID       │    │ Block by default │    │ No WiFi default │
│ Detection       │    │ Allow prefixes   │    │ Specific routes │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────────────┐
                    │   Zero Traffic Leakage  │
                    │     Guaranteed          │
                    └─────────────────────────┘
```

## Quick Start

### Prerequisites

- macOS (tested on macOS 10.15+)
- Administrative privileges (sudo access)
- Required tools: `jq`, `networksetup`, `route`, `pfctl`, `scutil`

Install missing dependencies:
```bash
# Install jq if not present
brew install jq
```

### Installation

1. **Clone or download the repository**
   ```bash
   git clone <repository-url>
   cd wifi-daemon
   ```

2. **Test the configuration**
   ```bash
   ./bin/test-routing.sh
   ```

3. **Install the system** (requires sudo)
   ```bash
   sudo ./bin/setup.sh install
   ```

4. **Verify installation**
   ```bash
   ./bin/setup.sh status
   ```

### Configuration

Edit the configuration files to match your environment:

#### Main Configuration (`config/config.json`)
```json
{
  "target_ssid": "SOME-SSID",
  "wifi_interface": "auto",
  "security_layers": {
    "firewall": true,
    "routing": true
  }
}
```

#### Network Prefixes (`config/prefixes.conf`)
```bash
# Include these networks through WiFi
10.0.0.0/8
172.16.0.0/12  
192.168.0.0/16

# Exclude these specific subnets (use default route)
!10.219.0.0/16
!10.52.0.0/16
!172.16.0.0/16
!192.168.1.0/24
```

## Usage

### Manual Operation

```bash
# Check current status
wifi-daemon status

# Start daemon manually
sudo wifi-daemon daemon

# Stop daemon
sudo wifi-daemon stop
```

### Automatic Operation

The system runs automatically as a LaunchDaemon:

```bash
# Check daemon status
sudo launchctl list | grep wifi-daemon

# Manually load/unload daemon
sudo launchctl load /Library/LaunchDaemons/com.wifi-daemon.plist
sudo launchctl unload /Library/LaunchDaemons/com.wifi-daemon.plist
```

### Testing and Verification

```bash
# Run full test suite
./bin/test-routing.sh

# Test specific components
./bin/test-routing.sh firewall
./bin/test-routing.sh routing

# Monitor network state
./bin/network-monitor status

# Check firewall rules
sudo ./bin/firewall-manager status en1

# Check routing state
./bin/route-manager status en1
```

## Components

### Core Scripts

| Script | Purpose |
|--------|---------|
| [`bin/wifi-daemon`](bin/wifi-daemon) | Main daemon - orchestrates the entire system |
| [`bin/firewall-manager`](bin/firewall-manager) | Manages pfctl firewall rules |
| [`bin/route-manager`](bin/route-manager) | Manages routing table entries |
| [`bin/network-monitor`](bin/network-monitor) | Network state monitoring utilities |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| [`bin/setup.sh`](bin/setup.sh) | System installation and configuration |
| [`bin/test-routing.sh`](bin/test-routing.sh) | Comprehensive test suite |

### Configuration Files

| File | Purpose |
|------|---------|
| [`config/config.json`](config/config.json) | Main system configuration |
| [`config/prefixes.conf`](config/prefixes.conf) | Network prefix definitions |

## How It Works

### Connection Detection
1. Monitors WiFi using `scutil` and `networksetup`
2. Detects connection to target SSID (SOME-SSID)
3. Validates DHCP lease and gateway reachability

### Security Configuration
1. **Firewall First**: Installs pfctl rules to block all WiFi traffic by default
2. **Route Management**: Removes WiFi default route, adds specific prefix routes
3. **Verification**: Confirms no traffic leakage is possible

### Traffic Flow Control
```
Internet Traffic (e.g., 8.8.8.8)
    ↓
Default Route (NOT WiFi) ──────────▶ Primary Interface (Ethernet/Cellular)

Configured Prefixes (e.g., 10.1.1.1)
    ↓
Specific Routes ─────────────────────▶ WiFi Interface (SOME-SSID)
```

### Disconnection Cleanup
1. Removes firewall rules
2. Cleans up WiFi-specific routes
3. Restores original routing state

## Security Features

### Dual-Layer Protection

1. **Firewall Layer (Primary)**
   - Blocks all outbound traffic on WiFi interface by default
   - Allows only configured network prefixes
   - Logs blocked traffic attempts

2. **Routing Layer (Secondary)**
   - Ensures WiFi never becomes default route
   - Installs interface-scoped routes for allowed prefixes
   - Preserves original default route

### Zero Leakage Guarantee

The combination of firewall and routing ensures that even if:
- Routes are misconfigured → Firewall blocks unauthorized traffic
- Firewall rules fail → No routes exist for unauthorized traffic
- Both layers fail → Traffic still goes through original default route

## File Locations

After installation:

```
/usr/local/bin/wifi-daemon/     # Main installation
├── wifi-daemon                 # Main daemon
├── firewall-manager               # Firewall management
├── route-manager                  # Route management  
└── network-monitor                # Network monitoring

/etc/wifi-daemon/              # Configuration
├── config.json                    # Main configuration
├── prefixes.conf                  # Network prefixes
└── pf-wifi.conf                   # Generated firewall rules

/var/lib/wifi-daemon/          # Runtime data
├── backups/                       # Route backups
├── logs/                          # Log files
└── state/                         # State files

/Library/LaunchDaemons/
└── com.wifi-daemon.plist      # System service
```

## Logging

Logs are written to:
- `/var/lib/wifi-daemon/logs/wifi-daemon.log` (main log)
- `/var/lib/wifi-daemon/logs/daemon.log` (daemon stdout)
- `/var/lib/wifi-daemon/logs/daemon-error.log` (daemon stderr)

Log levels: INFO, WARN, ERROR

## Important Notes

### Broken macOS Commands

⚠️ **DO NOT USE `networksetup -getairportnetwork`** - This command is broken and unreliable on modern macOS systems. It returns useless output like "associated with an AirPort network." instead of the actual SSID name.

**Use instead**: `system_profiler SPAirPortDataType` which provides reliable WiFi network information.

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Ensure running as root for system operations
sudo wifi-daemon status
```

**2. WiFi Interface Not Detected**
```bash
# Check available interfaces
networksetup -listallhardwareports

# Manually specify interface in config.json
"wifi_interface": "en0"
```

**3. Firewall Rules Not Applied**
```bash
# Check pfctl status
sudo pfctl -s info

# Test rule syntax
sudo pfctl -nf /etc/wifi-daemon/pf-wifi.conf
```

**4. Routes Not Working**
```bash
# Check routing table
netstat -rn | grep <wifi_interface>

# Verify default route is NOT via WiFi
route -n get default
```

### Debug Mode

Enable detailed logging by modifying the log level in scripts or running components manually:

```bash
# Run firewall manager manually
sudo ./bin/firewall-manager generate en1 config/prefixes.conf
sudo ./bin/firewall-manager apply en1

# Run route manager manually
sudo ./bin/route-manager configure en1 <gateway> config/prefixes.conf

# Monitor network changes
./bin/network-monitor monitor SOME-SSID
```

## Uninstallation

```bash
# Stop and remove the system
sudo ./bin/setup.sh uninstall
```

This will:
- Stop the daemon
- Remove all installed files
- Optionally remove configuration and data

## Contributing

1. Test any changes with the test suite
2. Ensure all scripts remain executable
3. Update documentation for new features
4. Follow the existing logging and error handling patterns

## License

This project is provided as-is for educational and operational use.

## Support

For issues or questions:
1. Run the test suite: `./bin/test-routing.sh`
2. Check logs: `tail -f /var/lib/wifi-daemon/logs/wifi-daemon.log`
3. Verify configuration: `jq . /etc/wifi-daemon/config.json`