# 📡 OpenWrt IP Presence Monitor

This OpenWrt service provides reliable, real-time device presence detection by monitoring the router's ARP table. It packages device status (online/offline), MAC, hostname, and ARP status into a single JSON message and publishes it via MQTT.

This method avoids unreliable **ICMP (ping)** checks, ensuring accurate status even for devices (like phones) that enter deep sleep.

## Features

  - **Reliable Presence:** Uses the ARP table (`ip neigh show`) for robust detection, ignoring devices that block ping.
  - **Accurate Status:** Distinguishes between active states (`REACHABLE`, `STALE`, `DELAY`) and inactive states (`FAILED`).
  - **Rich Data:** Publishes a single JSON payload containing IP, MAC, Hostname, and detailed ARP status.
  - **Home Assistant Integration:** Designed for simple integration using the MQTT Binary Sensor platform.
  - **`procd` Management:** Runs reliably every **10 seconds** via an OpenWrt init script.

## Prerequisites 🛠️

On your OpenWrt router:

  - **SSH Access**
  - **Required Packages:**
    ```bash
    opkg update
    opkg install mosquitto-client awk
    ```
  - **MQTT Broker:** Accessible with configured topic and credentials.

-----

## Installation Steps 🚀

### 1\. File Placement

Copy your two files to the following paths on your OpenWrt router:

| File Name | Destination Path | Purpose |
| :--- | :--- | :--- |
| `ip_monitor.sh` | `/usr/bin/ip_monitor.sh` | Main executable script. |
| `ip_monitor` | `/etc/init.d/ip_monitor` | System startup/service control file. |

After copying, ensure the main script is executable:

```bash
chmod +x /usr/bin/ip_monitor.sh
```

### 2\. Configure Credentials and IPs (Crucial\!)

You **must** edit the **`/usr/bin/ip_monitor.sh`** file to set your MQTT credentials and the list of IP addresses you want to monitor.

```bash
# ... lines 4-9 in ip_monitor.sh
MQTT_HOST="<YOUR_HA_IP>"        # Replace with your Home Assistant/MQTT Broker IP
MQTT_PORT="1883"                # Replace with your MQTT Broker Port
MQTT_USER="<YOUR_MQTT_USER>"    # Replace with your MQTT Username
MQTT_PASS="<YOUR_MQTT_PASSWORD>"# Replace with your MQTT Password
MQTT_TOPIC="openwrt/presence/device_status" 
TARGET_IPS="192.168.1.10 192.168.1.20 192.168.1.30" # Space separated list of IPs to track
# ...
```

### 3\. Enable and Start the Service

The init script will automatically run the monitor script every **10 seconds**.

```bash
# Enable the service to run on boot
/etc/init.d/ip_monitor enable

# Start the service immediately
/etc/init.d/ip_monitor start
```

-----

## Home Assistant Configuration 🏠

For each IP address you are monitoring, you must define a separate **MQTT Binary Sensor** in your Home Assistant configuration (e.g., `configuration.yaml`).

The sensor uses the `value_json.status` field for the main presence state (`on`/`off`) and extracts all other rich data as entity attributes.

### Configuration Template

```yaml
mqtt:
  binary_sensor:
    # --- Presence Sensor for 192.168.1.10 (e.g., My Phone) ---
    - name: "My Phone Presence"
      unique_id: device_presence_192_168_1_10
      state_topic: "openwrt/presence/device_status/192_168_1_10"
      
      # The main state is extracted from the JSON body
      value_template: "{{ value_json.status }}" 
      
      # Map payload to Home Assistant states
      payload_on: "online"
      payload_off: "offline"
      
      device_class: "presence" # Standard Home Assistant presence class
      
      # Extract all detailed information as attributes
      json_attributes_template: >
        {
          "IP Address": "{{ value_json.ip }}",
          "MAC Address": "{{ value_json.mac | upper }}",
          "Hostname": "{{ value_json.hostname }}",
          "ARP Status": "{{ value_json.arp_status }}"
        }

    # Repeat the above block for every IP in your TARGET_IPS list, 
    # making sure to update the 'name', 'unique_id', and 'state_topic' suffixes.
```

### Final Step

1.  **Restart Home Assistant** to load the new MQTT entities.
2.  Your new entities (e.g., `binary_sensor.my_phone_presence`) will update every 10 seconds.
