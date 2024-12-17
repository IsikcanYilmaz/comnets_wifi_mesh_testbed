#!/usr/bin/env bash

cd $1
IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \# | grep -v testbed | grep -v localhost) )

fields=( mgmt_tx mgmt_tx_bytes mgmt_rx mgmt_rx_bytes forward_pkts forward_bytes tx tx_bytes tx_dropped )
# Produce delta jsons
for i in ${targets[@]}; do
	target=$(echo $i | awk '{print $2}')
	echo $target 
	before="$(cat "$target"_before_batman_stats.json | jq)"
	after="$(cat "$target"_after_batman_stats.json | jq)"
	
	new="{}"
	for f in ${fields[@]}; do
		beforeF=$(echo $before | jq ".$f")
		afterF=$(echo $after | jq ".$f")
		diffF=$(($afterF - $beforeF))
		new=$(echo $new | jq ".$f = $diffF")
	done
	
	echo "$new" > "$target"_diff_batman_stats.json
done

# consolidate delta jsons
consolidated="{}"
for i in $(ls | grep diff_batman_stats.json); do
	for f in ${fields[@]}; do
		currSum=$(echo $consolidated | jq ".$f")
		if [ "$currSum" == null ] ; then 
			currSum=0
		fi
		val=$(($currSum + $(cat $i | jq ".$f")))
		consolidated=$(echo $consolidated | jq ".$f = $val")
	done
done
echo "$consolidated" > total_batman_stats.json

# Add some more info there
# set -x 
total_batman_stats=$(echo "$consolidated")
tx=$(echo $total_batman_stats | jq ".tx")
tx_bytes=$(echo $total_batman_stats | jq ".tx_bytes")
mgmt_tx=$(echo $total_batman_stats | jq ".mgmt_tx")
mgmt_tx_bytes=$(echo $total_batman_stats | jq ".mgmt_tx_bytes")
forward_pkts=$(echo $total_batman_stats | jq ".forward_pkts")
forward_bytes=$(echo $total_batman_stats | jq ".forward_bytes")
total_sum_tx_pkts=$(($tx + $mgmt_tx + $forward_pkts))
total_sum_tx_bytes=$(($tx_bytes + $mgmt_tx_bytes + $forward_bytes))
mgmt_percent=$(bc <<< "scale=2; 100 * $mgmt_tx / $total_sum_tx_pkts") #$(( 100 * $mgmt_tx / $tx ))
mgmt_bytes_percent=$(bc <<< "scale=2; 100 * $mgmt_tx_bytes / $total_sum_tx_bytes")
forward_pkts_percent=$(bc <<< "scale=2; 100 * $forward_pkts / $total_sum_tx_pkts")
forward_bytes_percent=$(bc <<< "scale=2; 100 * $forward_bytes / $total_sum_tx_bytes")

echo $total_batman_stats | jq ".mgmt_percent=$mgmt_percent" | jq ".mgmt_bytes_percent=$mgmt_bytes_percent" | jq  ".forward_pkts_percent=$forward_pkts_percent" | jq ".forward_bytes_percent=$forward_bytes_percent" > total_batman_stats.json

cd -
