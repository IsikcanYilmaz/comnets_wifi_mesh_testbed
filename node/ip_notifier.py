#!/usr/bin/env python

import platform, os
from scapy.all import *

# Thank you chat gippity

target = "141.30.87.173"
payload = os.popen("uci get system.@system[0].hostname").read().strip()
packet = IP(dst=target)/ICMP()/payload

print(f"Sending payload {payload} to {target}")
send(packet)
