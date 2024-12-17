#!/usr/bin/env bash

# Installing yoursunny's ndn openwrt packages
# Need to happen in an order:
# libndn-cxx
# nfd
# ndnsec
# ndn-autoconfig
# nfd-service
# the rest except...
# nfd-luci needs to be last
opkg update
cd ~/node/yoursunny/
opkg install libndn-cxx0.8.1_0.8.1-r1_aarch64_cortex-a53.ipk
opkg install nfd_22.12-r1_aarch64_cortex-a53.ipk
opkg install ndnsec_0.8.1-r1_aarch64_cortex-a53.ipk
opkg install ndn-autoconfig_22.12-r1_aarch64_cortex-a53.ipk
opkg install nfd-service_0.0.20201115-r1_all.ipk
opkg install nfd-status-http_22.12-r1_aarch64_cortex-a53.ipk
opkg install nfd-luci_0.0.20201115-r1_all.ipk
for i in $(ls | grep ipk); do opkg install $i; done

# Just did a fresh installation of yoursunny ipks 

killall nfd

cp ~/node/nfd.conf /var/etc/ndn/
cp ~/node/nfd.conf /etc/ndn/

cp ~/node/mgmt.ndncert /var/etc/ndn
cp ~/node/mgmt.ndncert /etc/ndn

# nfd creates faces towards all interfaces. remove them.
# IFS=$'\n'; for i in $(nfdc face list | grep faceid); do echo $i | sed 's/faceid=//g' |awk '{print $1}'  ; done
