I've got you covered. Here is the concise main `README.md` for your repository, structured to introduce the collection and point to the dedicated project folders for details.

***

# 🤖 OpenWrt Router Services Collection

This repository is a collection of essential shell scripts and configuration files designed to enhance monitoring, automation, and data export on OpenWrt-based routers. These services use **MQTT** to push critical router data directly into automation platforms like Home Assistant.

## Projects Included

| Project Folder | Description | Key Functionality |
| :--- | :--- | :--- |
| **[Network Speed](./Network%20Speed/README.md)** | Provides **accurate, real-time internet speed (Mbit/s)** monitoring by sampling WAN interface I/O and publishing the calculated rate via MQTT. | 🌐 **Real-Time Bandwidth Usage** (Upload/Download) |
| **[New Device Monitor](./New%20Device%20Monitor/README.md)** | An intelligent script that detects and identifies new devices joining your network, publishing rich JSON data via MQTT. | 🔍 **New Device Detection** & MAC Type Identification |

For installation and configuration details, please see the **`README.md`** file within each respective project folder.