#!/usr/bin/env bash

sudo ip address flush dev enp1s0f0
sudo ip route flush dev enp1s0f0

sudo ip address add 192.168.6.66/24 brd + dev enp1s0f0
sudo ip route add 192.168.6.1 dev enp1s0f0

ip a show dev enp1s0f0
