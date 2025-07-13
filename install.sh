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

apt update
apt install wget curl git vim wireguard iptables iptables-persistent jq openresolv dnsmasq -y

echo "# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug $DEV_INTERFACE
iface $DEV_INTERFACE inet static
  address $HOST_IP/$HOST_CIDR
  gateway $GATEWAY_IP

# This is an autoconfigured IPv6 interface
iface $DEV_INTERFACE inet6 auto" > /etc/network/interfaces

echo "no-resolv
listen-address=127.0.0.1,$HOST_IP
bind-interfaces
server=8.8.8.8" > /etc/dnsmasq.conf

systemctl restart dnsmasq
