# OpenWrt MQTT Network Speed Monitor

This project monitors the real-time upload and download speeds of your OpenWrt router's interface and publishes the data to Home Assistant via MQTT.

The script calculates speeds (Mbit/s) accurately by measuring the actual time elapsed between reads, ensuring reliable metrics regardless of system load.

## 1\. Prerequisites 🛠️

### OpenWrt Router

  * **SSH Access** to your OpenWrt device.

  * **Required Packages:** Install the necessary utilities for MQTT and floating-point math:

    ```bash
    opkg update
    opkg install mosquitto-client awk
    ```

### Home Assistant

  * An operational **MQTT Broker** (e.g., Mosquitto add-on) with a defined username and password.

-----

## 2\. OpenWrt Configuration and Deployment 🚀

The project uses two files:

1.  **`network_speed.sh`**: The executable script that reads I/O, calculates speed, and publishes to MQTT.
2.  **`network_speed`**: The `procd` init script to ensure the monitor runs automatically every 5 seconds and restarts if it fails.

### 2.1. Copy Files

Copy your existing files to the following locations on your OpenWrt router:

| Source File | Destination Path | Purpose |
| :--- | :--- | :--- |
| `network_speed.sh` | `/usr/bin/network_speed.sh` | Main executable script. |
| `network_speed` | `/etc/init.d/network_speed` | System startup/service control file. |

After copying, ensure the main script is executable:

```bash
chmod +x /usr/bin/network_speed.sh
```

### 2.2. Edit Configuration (Required)

Before starting the service, you **MUST** edit the **`/usr/bin/network_speed.sh`** file to set your connection details:

```bash
# ... lines 1-5 ...
INTERFACE="pppoe-wan"         # ⬅️ Your WAN interface name
MQTT_HOST="<YOUR_HA_IP>"      # ⬅️ Home Assistant/MQTT Broker IP
MQTT_USER="<YOUR_MQTT_USER>"  # ⬅️ MQTT Username
MQTT_PASS="<YOUR_MQTT_PASSWORD>"# ⬅️ MQTT Password
# ... remaining lines ...
```

-----

### 2.3. Enable and Start the Service

Start the network monitor and ensure it runs automatically on boot:

```bash
# Enable the service to run on boot
/etc/init.d/network_speed enable

# Start the service immediately
/etc/init.d/network_speed start
```

-----

## 3\. Home Assistant Configuration 🏡

Add the following to your Home Assistant's `configuration.yaml` file under the `mqtt:` section. These sensors subscribe to the topics published by the OpenWrt script.

```yaml
mqtt:
  sensor:
    # --- Download Speed Sensor ---
    - name: "OpenWrt Internet Download Speed"
      unique_id: openwrt_internet_download_speed
      state_topic: "openwrt/speed/download"
      unit_of_measurement: "Mbit/s"
      device_class: "data_rate"
      state_class: "measurement"
      value_template: "{{ value | float | round(2) }}"
      icon: "mdi:download-network"
      
    # --- Upload Speed Sensor ---
    - name: "OpenWrt Internet Upload Speed"
      unique_id: openwrt_internet_upload_speed
      state_topic: "openwrt/speed/upload"
      unit_of_measurement: "Mbit/s"
      device_class: "data_rate"
      state_class: "measurement"
      value_template: "{{ value | float | round(2) }}"
      icon: "mdi:upload-network"
```

### Final Step

1.  **Restart Home Assistant** to load the new MQTT sensor configuration.
2.  Your sensors, **`sensor.openwrt_internet_download_speed`** and **`sensor.openwrt_internet_upload_speed`**, will now be available, updating every 5 seconds with accurate, real-time speed data.
