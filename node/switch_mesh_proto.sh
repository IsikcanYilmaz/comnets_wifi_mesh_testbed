#!/usr/bin/env bash

proto="$1"

if [ "$proto" == "batman" ]; then
	echo "[*] Enabling $proto"
	ifconfig br-lan down
	uci set wireless.wmesh.disabled='0'
	uci set wireless.wifinet3.disabled='1'
	uci commit wireless
	wifi
	service batmand start
	echo "$proto" > /root/current_mesh_proto

elif [ "$proto" == "hwmp" ]; then
	echo "[*] Enabling $proto"
	ifconfig br-lan down
	uci set wireless.wmesh.disabled='1'
	uci set wireless.wifinet3.disabled='0'
	uci commit wireless
	wifi
	service batmand stop
	echo "$proto" > /root/current_mesh_proto

else
	echo "[!] Unknown protocol argument $proto"
fi
