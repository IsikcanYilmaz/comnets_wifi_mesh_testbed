#!/usr/bin/env bash

# Following the tut at https://cgomesu.com/blog/Mesh-networking-openwrt-batman/

ifacename=$(uci add wireless wifi-iface)
# spitzId=$(echo $HOSTNAME | sed s/spitz//g)
spitzId=$(bash /root/node/find_who_i_am.sh | sed s/spitz//g)

uci batch << EOI
set wireless.$ifacename=wifi-iface
set wireless.$ifacename.device='radio0'
set wireless.$ifacename.network='mesh'
set wireless.$ifacename.mode='mesh'
set wireless.$ifacename.mesh_id='MeshCloud'
set wireless.$ifacename.encryption='sae'
set wireless.$ifacename.key='MeshPassword123'
set wireless.$ifacename.mesh_fwding='0'
set wireless.$ifacename.mesh_ttl='1'
set wireless.$ifacename.mcast_rate='24000'
set wireless.$ifacename.disabled='0'
EOI

uci changes
uci commit
uci rename wireless.$ifacename="wmesh"
uci commit

###########################################
ifacename=$(uci add network interface)

uci batch << EOI
set network.$ifacename.proto='batadv'
set network.$ifacename.routing_algo='BATMAN_IV'
set network.$ifacename.aggregated_ogms='1'
set network.$ifacename.ap_isolation='0'
set network.$ifacename.bonding='0'
set network.$ifacename.bridge_loop_avoidance='1'
set network.$ifacename.distributed_arp_table='1'
set network.$ifacename.fragmentation='1'
set network.$ifacename.gw_mode='off'
set network.$ifacename.hop_penalty='30'
set network.$ifacename.isolation_mark='0x00000000/0x00000000'
set network.$ifacename.log_level='0'
set network.$ifacename.multicast_mode='1'
set network.$ifacename.multicast_fanout='16'
set network.$ifacename.network_coding='0'
set network.$ifacename.orig_interval='1000'
EOI

uci changes
uci commit
uci rename network.$ifacename="bat0"
uci commit

###########################################
ifacename=$(uci add network interface)

uci batch << EOI
set network.$ifacename.proto='batadv_hardif'
set network.$ifacename.master='bat0'
set network.$ifacename.mtu='1560'
EOI

uci changes
uci commit
uci rename network.$ifacename="mesh"
uci commit

###########################################
# Create L3 interface and hook it up to our mesh
devname=$(uci add network device)

uci batch << EOI
set network.$devname.name='br-mesh'
set network.$devname.type='bridge'
add_list network.$devname.ports='bat0'
EOI

ifacename=$(uci add network interface)

uci batch << EOI
set network.$ifacename.device='br-mesh'
set network.$ifacename.proto='static'
set network.$ifacename.ipaddr='192.168.8.10$spitzId'
set network.$ifacename.netmask='255.255.255.0'
EOI

zonename=$(uci add firewall zone)

uci batch << EOI
set firewall.$zonename.name=meshl3
add_list firewall.$zonename.network='meshl3'
set firewall.$zonename.input=ACCEPT
set firewall.$zonename.output=ACCEPT
set firewall.$zonename.forward=ACCEPT
EOI

uci changes
uci commit
uci rename network.$ifacename="meshl3"
uci commit

echo "[*] Done. You may wanna reboot."
