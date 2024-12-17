#!/usr/bin/env bash

sudo ip address flush dev eno1 
sudo ip route flush dev eno1 

sudo ip address add 192.168.6.200/24 brd + dev eno1
sudo ip route add 192.168.6.66 dev eno1 

ip a show dev eno1 
