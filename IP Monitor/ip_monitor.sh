#!/bin/ash

# -----------------------------------------------------------------------------
# Configuration Section
# -----------------------------------------------------------------------------
MQTT_HOST="192.168.1.1"    # Home Assistant/MQTT Broker IP
MQTT_PORT="1883"           # MQTT Broker Port
MQTT_USER=""               # MQTT Username
MQTT_PASS=""               # MQTT Password
MQTT_TOPIC="openwrt/presence"

# List of IP addresses to monitor (Space separated)
TARGET_IPS="192.168.1.5 192.168.1.7"

# --- Function to get Hostname from DHCP Leases ---

get_hostname() {
    local ip_addr="$1"
    # Format: ExpiryTime MAC_Address IP_Address Hostname ClientID
    # We use awk to find the line matching the IP address ($3) and print the hostname ($4).
    hostname=$(awk -v ip="$ip_addr" '$3 == ip {print $4; exit}' /tmp/dhcp.leases)

    # Return the hostname or 'unknown' if not found
    echo "${hostname:-unknown}"
}

# --- Main Logic ---

echo "Starting JSON ARP monitor scan at $(date)"

for IP in $TARGET_IPS; do
    
    # 1. Query ARP for status and MAC
    # We query for the specific IP and capture the full output.
    ARP_OUTPUT=$(ip neigh show "$IP")

    # 2. Extract MAC address and ARP status from ARP_OUTPUT
    # If a line exists, awk extracts the MAC (4th field) and the Status (6th field).
    # If no line is found, MAC is empty, STATUS is 'FAILED'.
    MAC_ADDR=$(echo "$ARP_OUTPUT" | awk '{print $5}' 2>/dev/null)
    ARP_STATUS=$(echo "$ARP_OUTPUT" | awk '{print $NF}' 2>/dev/null)
    
    # Clean up variables if no entry was found
    if [ -z "$ARP_STATUS" ]; then
        ARP_STATUS="FAILED"
        MAC_ADDR="00:00:00:00:00:00"
    fi

    # 3. Determine simple connectivity status
    # Consider any state that isn't FAILED/INCOMPLETE as online
    if echo "$ARP_STATUS" | grep -q 'REACHABLE\|STALE\|DELAY\|PERMANENT'; then
        STATUS="online"
    else
        STATUS="offline"
    fi

    # 4. Get Hostname
    HOST_NAME=$(get_hostname "$IP")

    # 5. Build the JSON payload
    # Note: Hostname is enclosed in quotes inside the awk script
    JSON_PAYLOAD=$(echo | awk -v ip="$IP" -v mac="$MAC_ADDR" -v name="$HOST_NAME" -v arp="$ARP_STATUS" -v status="$STATUS" '
        BEGIN {
            # Standard JSON formatting. We escape the quotes for the string values.
            printf "{\"ip\":\"%s\", \"mac\":\"%s\", \"hostname\":\"%s\", \"arp_status\":\"%s\", \"status\":\"%s\"}", ip, mac, name, arp, status
        }
    ')
    
    # 6. Publish the JSON body to a unique topic that includes the IP suffix
    TOPIC_SUFFIX=$(echo "$IP" | sed 's/\./_/g')
    
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "${MQTT_TOPIC}/${TOPIC_SUFFIX}" -m "$JSON_PAYLOAD" -q 1

    echo "Published $IP data: $JSON_PAYLOAD"
done

echo "Scan complete."
