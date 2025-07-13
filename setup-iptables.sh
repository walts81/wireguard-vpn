#!/bin/bash

set -e

# Variables
LAN_SUBNET="$HOST_SUBNET/$HOST_CIDR"
GATEWAY="$GATEWAY_IP/$HOST_CIDR"
DNS_PORT=53
ROUTE_TABLE_NAME="dns-bypass"
ROUTE_TABLE_ID=1001

mkdir -p /etc/iproute2

# Ensure net.ipv4.ip_forward is enabled and idempotently added to sysctl.conf
if grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf; then
    sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
else
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
fi

# Apply the change immediately
sysctl -w net.ipv4.ip_forward=1

echo "[+] Removing existing MASQUERADE rules for $WG_INTERFACE..."

# Loop through and delete all matching MASQUERADE rules
while iptables -t nat -C POSTROUTING -o "$WG_INTERFACE" -s "$LAN_SUBNET" -j MASQUERADE 2>/dev/null; do
  iptables -t nat -D POSTROUTING -o "$WG_INTERFACE" -s "$LAN_SUBNET" -j MASQUERADE
  echo "  [-] Removed duplicate MASQUERADE rule"
done

echo "[+] Ensuring MASQUERADE rule exists..."
# Only add MASQUERADE rule if it doesn't already exist
if ! iptables -t nat -C POSTROUTING -s "$LAN_SUBNET" -o "$WG_INTERFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WG_INTERFACE" -j MASQUERADE
    echo "  [+] MASQUERADE rule added."
else
    echo "  [-] MASQUERADE rule already exists."
fi

echo "[+] Ensuring DNS INPUT rules exist for $LAN_SUBNET..."

# UDP
if ! iptables -C INPUT -p udp --dport $DNS_PORT -s "$LAN_SUBNET" -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p udp --dport $DNS_PORT -s "$LAN_SUBNET" -j ACCEPT
    echo "  [+] UDP DNS rule added."
else
    echo "  [-] UDP DNS rule already exists."
fi

# TCP
if ! iptables -C INPUT -p tcp --dport $DNS_PORT -s "$LAN_SUBNET" -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p tcp --dport $DNS_PORT -s "$LAN_SUBNET" -j ACCEPT
    echo "  [+] TCP DNS rule added."
else
    echo "  [-] TCP DNS rule already exists."
fi

# Ensure variables are set
if [ -z "$DNS_1" ] || [ -z "$DNS_2" ]; then
  echo "DNS_1 and DNS_2 must be defined before running this script."
  exit 1
fi

echo "[+] Creating custom routing table (if needed)..."
if ! grep -q "^${ROUTE_TABLE_ID}[[:space:]]\+${ROUTE_TABLE_NAME}$" /etc/iproute2/rt_tables; then
  echo "${ROUTE_TABLE_ID} ${ROUTE_TABLE_NAME}" >> /etc/iproute2/rt_tables
  echo "  [+] Added ${ROUTE_TABLE_NAME} to /etc/iproute2/rt_tables"
else
  echo "  [-] Route table already present."
fi

echo "[+] Adding routes to $DNS_1 and $DNS_2 via $GATEWAY_IP..."
for dns in "$DNS_1" "$DNS_2"; do
  if ! ip route show table "$ROUTE_TABLE_NAME" | grep -q "^${dns} "; then
    ip route add "$dns" via "$GATEWAY_IP" dev "$DEV_INTERFACE" table "$ROUTE_TABLE_NAME"
    echo "  [+] Route to $dns added in table $ROUTE_TABLE_NAME"
  else
    echo "  [-] Route to $dns already exists in $ROUTE_TABLE_NAME"
  fi
done

echo "[+] Adding IP rules for DNS servers..."
for dns in "$DNS_1" "$DNS_2"; do
  if ! ip rule show | grep -q "to ${dns} lookup ${ROUTE_TABLE_NAME}"; then
    ip rule add to "$dns" lookup "$ROUTE_TABLE_NAME" priority 100
    echo "  [+] Rule for $dns added to lookup $ROUTE_TABLE_NAME"
  else
    echo "  [-] Rule for $dns already exists"
  fi
done

echo "[✓] DNS routing rules configured."

echo "[+] Saving iptables rules for persistence..."
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
fi

echo "[✓] iptables rules updated and persisted."

# Replace the upstream DNS in dnsmasq.conf
sed -i '/^server=/d' /etc/dnsmasq.conf
echo "server=$DNS_1" | sudo tee -a /etc/dnsmasq.conf
echo "server=$DNS_2" | sudo tee -a /etc/dnsmasq.conf

# Restart dnsmasq to apply
systemctl restart dnsmasq

echo "[✓] DNS IPs have been added to dnsmasq config and dnsmasq service has been restarted."
return 0
