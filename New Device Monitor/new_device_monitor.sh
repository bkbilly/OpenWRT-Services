#!/bin/sh
# New Device Monitor for OpenWRT
# Detects new devices via DHCP leases and ARP table, publishes to MQTT.

# --- Configuration ---
MQTT_TOPIC="openwrt/network/new_device"     # <--- Replace with your desired MQTT topic
MQTT_BROKER="192.168.1.1"                   # <--- Replace with your MQTT broker IP/hostname
MQTT_PORT="1883"                            # <--- Replace with your MQTT broker port if different
MQTT_USERNAME=""                            # <--- Replace with your MQTT username if authentication is required
MQTT_PASSWORD=""                            # <--- Replace with your MQTT password if authentication is required
ARP_SCAN_INTERVAL=60                        # Seconds between neighbor table scans
KNOWN_DEVICES_FILE="/etc/new_device_monitor/known_devices.txt"
IP_HOSTNAME_MAP_FILE="/etc/new_device_monitor/ip_hostname_map.txt"

# --- Functions ---

# Function to log messages with timestamp
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "/var/log/new_device_monitor.log"
}

# Function to escape string for JSON
json_escape() {
    # Basic JSON string escaping (handles double quotes and backslashes)
    echo "$1" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g'
}

# Function to load/refresh the IP-to-Hostname map from dhcp.leases
load_dhcp_leases_map() {
    log_message "Loading/Refreshing IP-to-Hostname map from /tmp/dhcp.leases..."
    # Clear the existing map file
    > "$IP_HOSTNAME_MAP_FILE"
    # Read dhcp.leases and populate the map (IP_ADDRESS HOSTNAME)
    # Ex: timestamp mac_address ip_address hostname client_id
    cat /tmp/dhcp.leases 2>/dev/null | while read -r _ mac_address ip_address hostname _; do
        # Sanitize hostname: if it's empty, '*', or '-', treat as truly empty
        local sanitized_hostname="$hostname"
        if [ "$sanitized_hostname" = "*" ] || [ "$sanitized_hostname" = "-" ] || [ -z "$sanitized_hostname" ]; then
            sanitized_hostname=""
        fi

        if [ -n "$ip_address" ] && [ -n "$sanitized_hostname" ]; then
            echo "$ip_address $sanitized_hostname" >> "$IP_HOSTNAME_MAP_FILE"
        fi
    done
    log_message "IP-to-Hostname map refreshed. Entries: $(wc -l < "$IP_HOSTNAME_MAP_FILE")"
}

# Function to lookup hostname by IP from the in-memory map or via DNS
lookup_hostname_by_ip() {
    local ip_to_lookup="$1"
    local hostname=""

    # 1. Try to find in the DHCP leases map first
    hostname=$(grep -E "^$ip_to_lookup " "$IP_HOSTNAME_MAP_FILE" | awk '{print $2}' | head -n1)

    # 2. If not found in DHCP leases map, try nslookup for reverse DNS lookup
    if [ -z "$hostname" ]; then
        local nslookup_output
        # nslookup output is generally more parseable than dig for this purpose in busybox/OpenWrt
        # Use +short to get minimal output, and filter out the IP itself if it appears.
        nslookup_output=$(nslookup "$ip_to_lookup" 2>/dev/null | \
                            grep -E "name = |Name:" | \
                            awk '{print $NF}' | \
                            sed 's/\.$//' | \
                            grep -vE "^$ip_to_lookup$")

        if [ -n "$nslookup_output" ]; then
            # Take the first non-empty result, if multiple
            hostname=$(echo "$nslookup_output" | head -n1)
        fi

        # Final sanitization for hostnames obtained via DNS lookup
        if [ "$hostname" = "*" ] || [ "$hostname" = "-" ] || [ -z "$hostname" ]; then
            hostname=""
        fi
    fi

    echo "$hostname"
}

# Function to publish a message to MQTT
publish_mqtt() {
    local message="$1"
    log_message "Attempting to publish to MQTT."

    # Append the message using -m. Use printf %b to handle potential backslashes in JSON correctly.
    # We use printf %b to properly interpret backslash escapes within the JSON message
    # And then pipe it to mosquitto_pub
    local pub_output
    printf %b $message | mosquitto_pub -h $MQTT_BROKER -p $MQTT_PORT -t $MQTT_TOPIC -u $MQTT_USERNAME -P $MQTT_PASSWORD -l
}

# Function to add a new device to the known list and notify
add_and_notify_device() {
    local mac="$1"
    local ip="$2"
    local source="$3" # 'DHCP' or 'Neighbor Table'
    local hostname="$4" # Passed in, or looked up for Neighbor Table entries

    # Check if the device is already known
    if grep -q -i "^$mac$" "$KNOWN_DEVICES_FILE"; then
        return # Device already known, do not notify again
    fi

    local current_time=$(date +'%Y-%m-%dT%H:%M:%S%z') # ISO 8601 format

    log_message "New device detected: MAC=$mac, IP=$ip, Hostname=$hostname, Source=$source"

    # Add to known devices file
    echo "$mac" >> "$KNOWN_DEVICES_FILE"

    # Determine MAC type (random vs. physical)
    # The second hexadecimal digit of the first octet determines if it's locally administered (randomized)
    # 0x02, 0x06, 0x0A, 0x0E (i.e., second bit is set)
    local first_octet_hex=$(echo "$mac" | cut -d: -f1)
    local second_nibble=${first_octet_hex:1:1} # Get the second char of the first octet (e.g., 'A' from '0A')
    local mac_type="physical" # Default to physical

    case "$second_nibble" in
        2|6|A|E|a|e) # Case-insensitive check
            mac_type="random"
            ;;
        *)
            # Do nothing, remains "physical"
            ;;
    esac

    # Construct JSON MQTT message
    local json_msg="{"
    json_msg="${json_msg}\"timestamp\": \"$(json_escape "$current_time")\","
    json_msg="${json_msg}\"mac\": \"$(json_escape "$mac")\","
    json_msg="${json_msg}\"ip\": \"$(json_escape "$ip")\","
    json_msg="${json_msg}\"source\": \"$(json_escape "$source")\"," # Added comma here
    json_msg="${json_msg}\"mac_type\": \"$(json_escape "$mac_type")\"" # New field

    # Only add hostname if it's not empty after sanitization
    if [ -n "$hostname" ]; then
        json_msg="${json_msg},\"hostname\": \"$(json_escape "$hostname")\""
    fi
    json_msg="${json_msg}}"

    log_message "JSON Msg: $json_msg"
    publish_mqtt "$json_msg"
}

# --- Main Logic ---

# Add an initial sleep to allow network services to fully come up
log_message "Initial wait to allow network to initialize..."
sleep 10 # Increased initial sleep for better network initialization
log_message "Initial sleep complete. Starting main monitor logic."

# Create the known devices file if it doesn't exist
if [ ! -f "$KNOWN_DEVICES_FILE" ]; then
    touch "$KNOWN_DEVICES_FILE"
    log_message "Created known devices file: $KNOWN_DEVICES_FILE"
fi

# Load the initial DHCP leases map
load_dhcp_leases_map

log_message "Starting new device monitor..."

# Initial population of known devices from current IP neighbor table
log_message "Initial neighbor table scan to populate known devices..."
# Using 'ip neigh show' to get IP and MAC addresses
# Example: 192.168.1.100 dev br-lan lladdr 00:11:22:33:44:55 REACHABLE
ip neigh show | while read -r line; do
    # Only process lines that have a MAC address (lladdr) and are REACHABLE
    if echo "$line" | grep -q "lladdr" && echo "$line" | grep -q "REACHABLE"; then
        # Extract IP address (1st field) and MAC address (5th field)
        ip=$(echo "$line" | awk '{print $1}')
        mac=$(echo "$line" | awk '{print $5}')

        if [ -n "$mac" ] && echo "$mac" | grep -q ":"; then
            # Add only MAC to the known file without notifying
            if ! grep -q -i "^$mac$" "$KNOWN_DEVICES_FILE"; then
                echo "$mac" >> "$KNOWN_DEVICES_FILE"
            fi
        fi
    fi
done
log_message "Initial neighbor table scan complete. Known devices count: $(wc -l < "$KNOWN_DEVICES_FILE")"

# Start monitoring loop
while true; do
    # 1. Monitor DHCP leases
    # Use tail -F (follow by name) to handle log rotation/recreation of dhcp.leases
    # This reads new lines from the file as they appear.
    # The 'stdbuf -oL' ensures output is line-buffered for piping.
    # The subshell handles the tail command, allowing the main script to continue for ARP.
    (
        log_message "Monitoring DHCP leases file: /tmp/dhcp.leases"
        # Initial read of existing leases to avoid notifying on old ones on script restart
        # These are already loaded by load_dhcp_leases_map, so no need to re-add to known_devices
        # but we refresh the map to ensure it's current.
        load_dhcp_leases_map # Refresh map after initial read of old leases

        # Now, continuously watch for new leases
        stdbuf -oL tail -F /tmp/dhcp.leases 2>/dev/null | while read -r timestamp mac_address ip_address hostname client_id; do
            # Refresh the map whenever a new DHCP lease line appears
            load_dhcp_leases_map

            if [ -n "$mac_address" ] && echo "$mac_address" | grep -q ":"; then
                # Sanitize hostname: if it's empty, '*', or '-', treat as truly empty
                local sanitized_hostname="$hostname"
                if [ "$sanitized_hostname" = "*" ] || [ "$sanitized_hostname" = "-" ] || [ -z "$sanitized_hostname" ]; then
                    sanitized_hostname=""
                fi
                add_and_notify_device "$mac_address" "$ip_address" "DHCP" "$sanitized_hostname"
            fi
        done
    ) & # Run DHCP monitoring in a background subshell
    DHCP_PID=$! # Get PID of the DHCP monitor subshell

    # 2. Periodically scan IP neighbor table
    LAST_ARP_SCAN=$(date +%s)
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED_TIME=$((CURRENT_TIME - LAST_ARP_SCAN))

        if [ "$ELAPSED_TIME" -ge "$ARP_SCAN_INTERVAL" ]; then
            log_message "Performing IP neighbor table scan..."
            # Iterate through ip neigh show output
            # Example: 192.168.1.100 dev br-lan lladdr 00:11:22:33:44:55 REACHABLE
            ip neigh show | while read -r line; do
                # Only process lines that have a MAC address (lladdr) and are REACHABLE
                if echo "$line" | grep -q "lladdr" && echo "$line" | grep -q "REACHABLE"; then
                    # Extract IP address (1st field) and MAC address (5th field)
                    ip=$(echo "$line" | awk '{print $1}')
                    mac=$(echo "$line" | awk '{print $5}')

                    if [ -n "$mac" ] && echo "$mac" | grep -q ":"; then
                        # Lookup hostname from the DHCP leases map
                        resolved_hostname=$(lookup_hostname_by_ip "$ip")
                        add_and_notify_device "$mac" "$ip" "Neighbor Table" "$resolved_hostname"
                    fi
                fi
            done
            LAST_ARP_SCAN="$CURRENT_TIME"
            log_message "IP neighbor table scan complete."
        fi
        sleep 5 # Check every 5 seconds if enough time has passed for scan
    done

    # This part theoretically should not be reached if the inner while true is infinite.
    # However, if any sub-process fails, we might end up here.
    # So we restart the main loop.
    log_message "Main loop restarting..."
    sleep 5
done
