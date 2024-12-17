#!/usr/bin/env bash
#
uci del wireless.radio1.disabled
# uci set wireless.wifinet1=wifi-iface
# uci set wireless.wifinet1.device='radio1'
# uci set wireless.wifinet1.mode='ap'
# uci set wireless.wifinet1.ssid='OpenWrt'
# uci set wireless.wifinet1.encryption='none'
uci set wireless.wifinet2=wifi-iface
uci set wireless.wifinet2.device='radio1'
uci set wireless.wifinet2.mode='ap'
uci set wireless.wifinet2.ssid='vidya_mesh_'$HOSTNAME
uci set wireless.wifinet2.encryption='psk2'
uci set wireless.wifinet2.key='vidyameshvidyamesh'
uci set wireless.wifinet2.network='meshl3'
uci set wireless.radio1.cell_density='0'
uci del wireless.wifinet1
uci commit wireless

uci set network.vidya=interface
uci set network.vidya.proto='none'
uci set network.vidya.device='phy1-ap0'
uci set network.vidya.proto='static'
uci set network.vidya.ipaddr='192.168.8.110'
uci set network.vidya.netmask='255.255.255.0'
uci commit network 

uci set dhcp.vidya=dhcp
uci set dhcp.vidya.interface='vidya'
uci set dhcp.vidya.ignore='1'
uci del dhcp.vidya.ignore
uci set dhcp.vidya.start='120'
uci set dhcp.vidya.limit='100'
uci set dhcp.vidya.leasetime='12h'
uci commit dhcp

# uci add firewall zone # =cfg0fdc81
# uci set firewall.@zone[-1].name='vidya'
# uci set firewall.@zone[-1].input='ACCEPT'
# uci set firewall.@zone[-1].output='REJECT'
# uci set firewall.@zone[-1].forward='REJECT'
# uci add_list firewall.@zone[-1].network='meshl3'
# uci add_list firewall.@zone[-1].network='vidya'
# uci commit firewall

wifi
