#!/usr/bin/env bash

cmd="$1" # load or unload
if [ "$cmd" == "load" ]; then
	insmod /lib/modules/6.6.52/batman-adv.ko
	service network restart
	echo "Batman_adv loaded"
elif [ "$cmd" == "unload" ]; then
	rmmod batman_adv
	echo "Batman_adv unloaded"
else
	echo "Usage ./load_unload_batman.sh <load | unload>"
	exit 1
fi
