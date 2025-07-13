#!/bin/bash
ENV_FILE="/opt/manual-connections/.env"

if [ -f "$ENV_FILE" ]; then
  set -o allexport # Export all subsequently defined variables
  source "$ENV_FILE"
  set +o allexport
else
  echo "Error: .env file not found at $ENV_FILE"
  exit 1
fi

set -euo pipefail

WG_INTERFACE="pia"
PREFERRED_REGION="us_chicago"
VPN_PROTOCOL="wireguard"
DISABLE_IPV6="yes"
AUTOCONNECT=false #this needs to be false so it will respect our "PREFERRED_REGION"
PIA_PF=false
PIA_DNS=true

# --- Step 1: Stop WG if it's already running ---
if ip link show "$WG_INTERFACE" &>/dev/null; then
  echo "WireGuard interface '$WG_INTERFACE' is up. Stopping it..."
  wg-quick down "$WG_INTERFACE"
  echo "Restoring real default route through LAN..."
  ip route replace default via "$GATEWAY_IP" dev "$DEV_INTERFACE"
  echo "Restoring DNS..."
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
fi

# --- Step 2: Generate a new PIA token
PIA_TOKEN=$(curl -s -u "$PIA_USER:$PIA_PASS" "https://privateinternetaccess.com/gtoken/generateToken" | jq -r '.token')
#echo "Your PIA Token has been retrieved successfully: $PIA_TOKEN"

export PIA_TOKEN
export WG_INTERFACE
export PREFERRED_REGION
export GATEWAY_IP
export DEV_INTERFACE
export VPN_PROTOCOL
export DISABLE_IPV6
export AUTOCONNECT
export PIA_PF
export PIA_DNS

# --- Step 3: run the Wireguard setup script
/opt/manual-connections/refresh-pia-config.sh

# --- Step 4: ensure iptable info is setup correctly
/opt/manual-connections/setup-iptables.sh

# --- Step 5: make sure our DNS is pointed at ourselves
#             we'll forward thru dnsmasq
echo "Restoring DNS..."
echo "nameserver 127.0.0.1" > /etc/resolv.conf
