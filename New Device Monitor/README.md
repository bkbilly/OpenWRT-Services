# OpenWRT New Device Monitor
This OpenWRT app identifies new network devices (DHCP/ARP), publishing detailed JSON messages to an MQTT topic. It includes device MAC, IP, hostname (if available), and MAC type (random/physical).

## Features
- New Device Detection: Monitors DHCP leases and ip neigh show for new devices.
- MQTT Notifications: Sends JSON messages with device details.
- Hostname Resolution: Uses DHCP leases and nslookup for hostnames.
- MAC Type Identification: Differentiates "physical" vs. "random" MACs.
- Minimal & Integrated: Shell script, minimal dependencies, procd managed for auto-start and stability.

## Prerequisites
On your OpenWRT router:
- SSH Access
- mosquitto-client: Install via `opkg update; opkg install mosquitto-client`.
- MQTT Broker: Accessible with configured topic and optional credentials.

## Installation Steps
Via SSH on OpenWRT:

### Step 1: Create Main Script
Create `/usr/bin/new_device_monitor.sh` and paste the script content. Customize MQTT variables!
```bash
vi /usr/bin/new_device_monitor.sh
# Paste script, save & exit
chmod +x /usr/bin/new_device_monitor.sh
```

### Step 2: Create Known Devices Directory
```bash
mkdir -p /etc/new_device_monitor
```

### Step 3: Create procd Init Script
Create `/etc/init.d/new_device_monitor` and paste the procd script content.
```bash
vi /etc/init.d/new_device_monitor
# Paste script, save & exit
chmod +x /etc/init.d/new_device_monitor
```

### Step 4: Enable & Start Service
```bash
/etc/init.d/new_device_monitor enable
/etc/init.d/new_device_monitor start
```

## Verification & Troubleshooting
- Service Status: `/etc/init.d/new_device_monitor status`
- Log File: `tail -f /var/log/new_device_monitor.log` (for detections & errors)
- Known Devices: `cat /etc/new_device_monitor/known_devices.txt`
- MQTT Monitor: Subscribe to your MQTT topic to see notifications.

## Common Issues
- MQTT Connection: Verify broker IP/port/credentials.
- Script Not Running: Check logread and new_device_monitor.log.
- Missing Hostnames: Ensure dnsmasq/DNS resolver is configured for reverse lookups.
- Permissions: Confirm scripts are executable (chmod +x).
