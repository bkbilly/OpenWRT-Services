#!/bin/ash

# Configuration
MQTT_TOPIC_DOWN="openwrt/speed/download"
MQTT_TOPIC_UP="openwrt/speed/upload"
INTERFACE="wan"         # Your WAN interface name
MQTT_HOST="192.168.1.1" # Replace with your Home Assistant/MQTT Broker IP
MQTT_PORT="1883"        # Replace with your MQTT Broker Port
MQTT_USER=""            # Your MQTT Username
MQTT_PASS=""            # Your MQTT Password

# Temporary files to store previous values and timestamp
PREV_RX_FILE="/tmp/${INTERFACE}_rx_prev"
PREV_TX_FILE="/tmp/${INTERFACE}_tx_prev"
PREV_TS_FILE="/tmp/${INTERFACE}_ts_prev"

# --- Main Logic ---

# 1. Read current byte counters and timestamp
CURRENT_RX_BYTES=$(cat /sys/class/net/${INTERFACE}/statistics/rx_bytes 2>/dev/null)
CURRENT_TX_BYTES=$(cat /sys/class/net/${INTERFACE}/statistics/tx_bytes 2>/dev/null)
CURRENT_TS=$(date +%s) # Current timestamp in seconds

# Exit if interface stats are not available
if [ -z "$CURRENT_RX_BYTES" ] || [ -z "$CURRENT_TX_BYTES" ]; then
    echo "Error: Cannot read statistics for interface ${INTERFACE}"
    exit 1
fi

# 2. Read previous values and exit if this is the first run
if [ ! -f "$PREV_TS_FILE" ]; then
    echo "First run, storing initial values..."
    echo "$CURRENT_RX_BYTES" > "$PREV_RX_FILE"
    echo "$CURRENT_TX_BYTES" > "$PREV_TX_FILE"
    echo "$CURRENT_TS" > "$PREV_TS_FILE"
    exit 0
fi

# 3. Read previous byte counters and timestamp
PREV_RX_BYTES=$(cat "$PREV_RX_FILE")
PREV_TX_BYTES=$(cat "$PREV_TX_FILE")
PREV_TS=$(cat "$PREV_TS_FILE")


# 4. Store current values for the next run
echo "$CURRENT_RX_BYTES" > "$PREV_RX_FILE"
echo "$CURRENT_TX_BYTES" > "$PREV_TX_FILE"
echo "$CURRENT_TS" > "$PREV_TS_FILE"


# 5. Calculate the difference (delta)
DELTA_RX=$((CURRENT_RX_BYTES - PREV_RX_BYTES))
DELTA_TX=$((CURRENT_TX_BYTES - PREV_TX_BYTES))
TIME_DELTA=$((CURRENT_TS - PREV_TS))

# Ensure time delta is positive and non-zero
if [ "$TIME_DELTA" -le 0 ]; then
    echo "Error: Time delta is non-positive ($TIME_DELTA). Exiting."
    exit 1
fi

# 6. Calculate speed in Mbit/s (using bc for floating point math)
# Formula: (Bytes_Delta * 8) / (Time_Delta * 1000000)

if [ "$DELTA_RX" -ge 0 ]; then
    # Use awk for floating point calculation
    DOWNLOAD_MBPS=$(awk -v rx="$DELTA_RX" -v ts="$TIME_DELTA" 'BEGIN { printf "%.3f", (rx * 8) / (ts * 1000000) }')
    # 6. Publish Download Speed with authentication
    mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT_TOPIC_DOWN" -m "$DOWNLOAD_MBPS" -q 1
fi

if [ "$DELTA_TX" -ge 0 ]; then
    # Use awk for floating point calculation
    UPLOAD_MBPS=$(awk -v tx="$DELTA_TX" -v ts="$TIME_DELTA" 'BEGIN { printf "%.3f", (tx * 8) / (ts * 1000000) }')
    # 6. Publish Upload Speed with authentication
    mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT_TOPIC_UP" -m "$UPLOAD_MBPS" -q 1
fi
