#!/usr/bin/env bash

# Usage: ash fresh.sh <ID (int)>
# This script is meant to be the first thing to run after doing `opkg install libc_1.2.5-r4_aarch64_cortex-a53.ipk` (which you should scp over to the router yourself)
# It will set the static IP address for the switched LAN network, download some required packages, set the time zone, and set the hostname of this machine

ID=$(bash /root/node/find_who_i_am.sh | sed 's/spitz//g')

if [ "$ID" == "" ]; then
	echo "[!] Please provide spitzbox id(int)"
	exit 1
fi

NAME="spitz$ID"
echo "[*] Fresh Spitz box ID: $ID. Setting up..."
echo "Hostname: $NAME"

function setup_lan()
{
	gateway="192.168.6.66"
	lan_addr="192.168.6.$((100+$ID))"
	echo "LAN Address set to $lan_addr"

	# Set our link local address # Better to do this manually
	uci set network.lan.ipaddr=$lan_addr
	uci set network.lan.gateway=$gateway

	# Set our DNS addresses
	uci set network.lan.dns='141.30.158.216 141.30.1.1'
	uci commit network

	# We dont want DHCP server running on the LAN port
	uci set dhcp.lan.dhcpv4='disabled' # 'server' to enable
	uci set dhcp.lan.dhcpv6='disabled'
	uci set dhcp.@dnsmasq[0].notinterface='lan'

	uci commit dhcp

	service network reload
	service dnsmasq enable && service dnsmasq restart
}

# Set hostname
uci set system.@system[0].hostname="$NAME"
uci commit system

# Set timezone (Eu/Berlin) # Default is UTC
uci set system.@system[0].timezone="CET-1CEST,M3.5.0,M10.5.0/3"

# If libc 1.2.5-r4 (or later) is not installed, python wont work!
[ "$(opkg info libc | grep Version | awk '{print $2}')" != "1.2.5-r4" ] && echo "[!] Upgrade your libc!"

# Install packages
opkg update
opkg install rsync python3 python3-dev python3-cffi python3-pip nmap at ntpdate ntp-utils bash procps-ng-pkill tcpdump luci-app-commands iperf3 shadow-chsh ethtool

# TODO i wonder if it makes more sense to install this during openwrt compilation
opkg remove wpad-basic* # https://cgomesu.com/blog/Mesh-networking-openwrt-batman/
opkg install luci-proto-batman-adv wpad-mesh-wolfssl 
opkg install --force-reinstall libpcap1
pip3 install ansible scapy

# Default shell should be bash
chsh -s /bin/bash

# Copy over the reset button functionality script
cp /root/node/reset /etc/rc.button/reset

# Set our date
ntpdate "pool.ntp.org"

# Set up batman
# bash /root/node/setup_batman.sh

echo "$NAME fresh.sh run at $(date)"

echo "[*] Done. Rebooting"

sleep 5
reboot now
