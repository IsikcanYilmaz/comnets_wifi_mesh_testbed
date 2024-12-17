#!/usr/bin/env bash

# Every once in a while the WAN port needs poking. this script sends my machine a ping and if the ping fails
# pokes the WAN port of the router
# Put this script in your crontab by doing crontab -e and putting the following
# */5 * * * * bash /root/node/wan_checker.sh  # Runs every 5 minutes
# service cron restart

target="141.30.87.173"
ping $target -c1 -W5 &>/dev/null # ping our target with one packet, timeout after 5 seconds
if [ "$?" -eq 1 ]; then
	logwrite "Cannot reach $target . Resetting WAN port"
	ifup wan
fi
