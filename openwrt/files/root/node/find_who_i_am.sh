#!/usr/bin/env bash

# This script figures out which spitz router this one is by checking it's eth0 mac address
#
# spitz0 94:83:C4:A0:23:E0
# spitz1 94:83:C4:A0:21:98
# spitz2 94:83:C4:A0:21:4C
# spitz3 94:83:C4:A0:23:2C
# spitz4 94:83:C4:A0:1E:A0

# indices correspond to spitz ids 
MACS=('94:83:C4:A0:23:E0' '94:83:C4:A0:21:98' '94:83:C4:A0:21:4C' '94:83:C4:A0:23:2C' '94:83:C4:A0:1E:A0')

function checkForMac()
{
	myMac=$1
	for i in $(seq 0 $((${#MACS[@]}-1)) ); do
		if [ $myMac == ${MACS[$i]} ]; then 
			# echo $i ${myMac[$i]}
			echo "spitz"$i
			return
		fi
	done
	>&2 echo $myMac could not be found
}

myMac=$(ifconfig eth0 | grep HWaddr | awk '{print $NF}')
checkForMac $myMac
