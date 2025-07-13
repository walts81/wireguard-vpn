#!/bin/bash

set -e

# Variables
LAN_SUBNET="$HOST_SUBNET/$HOST_CIDR"
GATEWAY="$GATEWAY_IP/$HOST_CIDR"

# Ensure net.ipv4.ip_forward is enabled and idempotently added to sysctl.conf
if grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf; then
    sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
else
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
fi

# Apply the change immediately
sysctl -w net.ipv4.ip_forward=1

echo "[+] Ensuring iptables-persistent is installed..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

echo "[+] Removing existing MASQUERADE rules for $WG_INTERFACE..."
# Get list of existing MASQUERADE rules in POSTROUTING
RULE_NUMS=$(iptables -t nat -L POSTROUTING --line-numbers | grep MASQUERADE | grep "$WG_INTERFACE" | awk '{print $1}' | tac)

for RULE_NUM in $RULE_NUMS; do
    iptables -t nat -D POSTROUTING "$RULE_NUM"
done

echo "[+] Adding MASQUERADE rule for $LAN_SUBNET via $WG_INTERFACE..."
iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WG_INTERFACE" -j MASQUERADE

DNS_PORT=53

# Check and add UDP DNS rule if not present
if ! iptables -C INPUT -p udp --dport $DNS_PORT -s "$GATEWAY" -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p udp --dport $DNS_PORT -s "$GATEWAY" -j ACCEPT
fi

# Check and add TCP DNS rule if not present
if ! iptables -C INPUT -p tcp --dport $DNS_PORT -s "$GATEWAY" -j ACCEPT 2>/dev/null; then
    iptables -A INPUT -p tcp --dport $DNS_PORT -s "$GATEWAY" -j ACCEPT
fi


echo "[+] Saving iptables rules for persistence..."
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
fi

echo "[+] iptables rules updated and persisted."

