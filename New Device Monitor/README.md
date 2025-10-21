# OpenWRT New Device Monitor

This OpenWRT app identifies new network devices (DHCP/ARP), publishing detailed JSON messages to an MQTT topic. It includes device MAC, IP, hostname (if available), and MAC type (random/physical).

## Features

  - **New Device Detection:** Monitors DHCP leases and `ip neigh show` for new devices.
  - **MQTT Notifications:** Sends JSON messages with device details.
  - **Hostname Resolution:** Uses DHCP leases and `nslookup` for hostnames.
  - **MAC Type Identification:** Differentiates "physical" vs. "random" MACs.
  - **Minimal & Integrated:** Shell script, minimal dependencies, `procd` managed for auto-start and stability.

## Prerequisites

On your OpenWRT router:

  - SSH Access
  - `mosquitto-client`: Install via `opkg update; opkg install mosquitto-client`.
  - **MQTT Broker:** Accessible with configured topic and optional credentials.

## Installation Steps

Via SSH on OpenWRT:

### Step 1: Create Main Script

Create `/usr/bin/new_device_monitor.sh` and paste the script content. **Customize MQTT variables\!**

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

Create `/etc/init.d/new_device_monitor` and paste the `procd` script content.

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

-----

## 🏠 Home Assistant Automation

Once the OpenWrt script is publishing device data to the MQTT topic (e.g., `openwrt/network/new_device`), you can set up an automation in Home Assistant to create a persistent notification and send a mobile alert.

This automation uses the `trigger.payload_json` object to parse the device details directly from the MQTT message.

```yaml
alias: New Network Device
description: "Notifies when the OpenWRT script detects a new MAC address."
mode: single
trigger:
  - platform: mqtt
    topic: openwrt/network/new_device
condition: []
action:
  # Action 1: Create a detailed persistent notification
  - service: persistent_notification.create
    metadata: {}
    data:
      message: |-
        | Detail | Value |
        |---|---|
        | **MAC** | {{ trigger.payload_json.mac | upper }} |
        | **IP** | {{ trigger.payload_json.ip }} |
        | **Hostname** | {{ trigger.payload_json.hostname }} |
        | **Type** | {{ trigger.payload_json.mac_type }} |
      title: New Device connected to the Network
  # Action 2: Send a mobile notification
  - service: notify.mobile_app_samsung
    metadata: {}
    data:
      message: >-
        Hostname: {{ trigger.payload_json.hostname }}
        IP: {{ trigger.payload_json.ip }} 
        MAC: {{ trigger.payload_json.mac | upper }} ({{ 
        trigger.payload_json.mac_type }})
      title: New network device
```

-----

## Verification & Troubleshooting

  - **Service Status:** `/etc/init.d/new_device_monitor status`
  - **Log File:** `tail -f /var/log/new_device_monitor.log` (for detections & errors)
  - **Known Devices:** `cat /etc/new_device_monitor/known_devices.txt`
  - **MQTT Monitor:** Subscribe to your MQTT topic to see notifications.

## Common Issues

  - **MQTT Connection:** Verify broker IP/port/credentials.
  - **Script Not Running:** Check `logread` and `new_device_monitor.log`.
  - **Missing Hostnames:** Ensure `dnsmasq`/DNS resolver is configured for reverse lookups.
  - **Permissions:** Confirm scripts are executable (`chmod +x`).
