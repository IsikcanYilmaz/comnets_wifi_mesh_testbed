# ComNets WiFi Mesh Testbed
Source and configs for TUD ComNets WiFi Mesh Testbed 

Consisting of 5 Spitz AX GL-X3000 Routers forming an 802.11s Mesh network

# Spitz AX Mesh router
- Spitz AX GL-X3000 5G/WiFi6 Router
- https://forum.openwrt.org/t/gl-inet-gl-x3000-spitz-ax-support/162143
- MediatTek Ralink ARM
- Filogic 8x0 MT798x (MT7981)
    DISTRIB_ID='OpenWrt'
    DISTRIB_RELEASE='SNAPSHOT'
    DISTRIB_REVISION='r25996-e0363233c9'
    DISTRIB_TARGET='mediatek/filogic'
    DISTRIB_ARCH='aarch64_cortex-a53'
    DISTRIB_DESCRIPTION='OpenWrt SNAPSHOT r25996-e0363233c9'
    DISTRIB_TAINTS=''
- Driver: mt7915e (https://github.com/openwrt/mt76.git)

# Instructions and Notes 

The `controller` directory has scripts and ansible configs that are meant to be run from your PC.

The `node` directory is meant to be placed in the router and contains scripts meant to run on the router. 

