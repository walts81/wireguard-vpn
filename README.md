## Setup WireGuard VPN (using Private Internet Access)

### Scripts:
- ./install.sh
- ./refresh-vpn.sh - the primary script to create the wireguard config and start the VPN
- ./refresh-pia-config.sh - contains most of what is needed to setup the Wireguard vpn and connect
- ./setup-iptables.sh - persists needed iptables rules

### Install
run ./install.sh
This script will install any apt packages necessary for the wireguard setup

### How it works
Running the ./refresh-vpn.sh script will then do the following...
- grab a new token for PIA access and set the PIA\_TOKEN env variable
- call the refresh-pia-config script which will refresh the wireguard conf, re-connect the wg interface (VPN) as well as setup ip routes
- call the setup-iptables script which sets up the necessary iptables rules to enable routing and DNS forwarding for VPN traffic, and ensures those rules persist across reboots.

An .env file needs to be present in the same directory with a few env variables...
- PIA\_USER
- PIA\_PASS
- DIP\_TOKEN (optional dedicated IP token)
- GATEWAY\_IP (IP address of your router/gateway)
- DEV\_INTERFACE (name of primary networking interface device... ex: eth0)
- HOST\_IP (IP address of the machine running wireguard)
- HOST\_SUBNET (ex: 192.168.0.0)
- HOST\_CIDR (ex: 8 or 16 or 24 or 32)

These scripts are idempotent and can be run at any time even if services are already running/connected.
Ideally a cron job should be created to run refresh-vpn.sh to keep the connection valid such as...
0 */12 * * * /opt/manual-connections/refresh-vpn.sh >> /var/log/refresh-vpn.log 2>&1
