#!/usr/bin/env bash

IW_IFACE="phy0-mesh0"

declare -A macs=( 
["94:83:c4:a0:23:e2"]="spitz0"
["94:83:c4:a0:21:9a"]="spitz1"
["94:83:c4:a0:21:4e"]="spitz2"
["94:83:c4:a0:23:2e"]="spitz3"
["94:83:c4:a0:1e:a2"]="spitz4"

["94:83:c4:a0:00:00"]="spitz0"
["94:83:c4:a0:00:01"]="spitz1"
["94:83:c4:a0:00:02"]="spitz2"
["94:83:c4:a0:00:03"]="spitz3"
["94:83:c4:a0:00:04"]="spitz4"

["94:83:c4:a0:11:00"]="spitz0"
["94:83:c4:a0:11:01"]="spitz1"
["94:83:c4:a0:11:02"]="spitz2"
["94:83:c4:a0:11:03"]="spitz3"
["94:83:c4:a0:11:04"]="spitz4"
)

# Returns wireless channel number (int)
function get_current_channel_num()
{
	iw dev $IW_IFACE info | grep channel | awk '{print $2}'
}

# Returns wireless channel frequency (MHz)
function get_current_channel_freq()
{
	iw dev $IW_IFACE info | grep channel | awk '{print $3}' | sed 's/(//g'
}

# Get currently set txpower value (dBm)
function get_current_txpower()
{
	iw dev $IW_IFACE info | grep txpower | awk '{print $2}' 
}

# Get the noise from the channel in use (dBm)
function get_noise_in_use()
{
	iw dev $IW_IFACE survey dump | grep "in\ use" -A1 | grep noise | awk '{print $2}'
}

# Not including broadcasts
function sum_per_station_tx_packets()
{
	sumPerStationTxPackets=$(iw dev $IW_IFACE station dump | grep "tx packets" | awk '{print $3}' | awk '{ sum += $1; } END {print sum}' "$@")
	prevSumPerStationTxPackets=$sumPerStationTxPackets
	echo $sumPerStationTxPackets
}

# Including broadcasts and rebroadcasts
function all_tx_packets()
{
	allTxPackets=$(iw dev $IW_IFACE info | grep "tx-packets" -A2 | grep -v "tx-packets" | awk -F " " '{print $NF}')
	prevAllTxPackets=$allTxPackets
	echo $allTxPackets
}

# BATMAN Statistics in json form
function get_batman_statistics_json()
{
	raw=$(batctl s)
	mgmt_tx=$(echo "$raw" | grep "mgmt_tx:" | awk '{print $2}')
	mgmt_tx_bytes=$(echo "$raw" | grep "mgmt_tx_bytes:" | awk '{print $2}')
	mgmt_rx=$(echo "$raw" | grep "mgmt_rx:" | awk '{print $2}')
	mgmt_rx_bytes=$(echo "$raw" | grep "mgmt_rx_bytes:" | awk '{print $2}')
	forward_pkts=$(echo "$raw" | grep "forward:" | awk '{print $2}')
	forward_bytes=$(echo "$raw" | grep "forward_bytes:" | awk '{print $2}')
	tx=$(echo "$raw" | grep "tx:" | grep -v "_" | awk '{print $2}')
	tx_bytes=$(echo "$raw" | grep "tx_bytes:" | grep -v "_tx" | awk '{print $2}')
	tx_dropped=$(echo "$raw" | grep "tx_dropped:" | grep -v "_tx" | awk '{print $2}')
	jsonout=$(jq -n \
		--argjson mgmt_tx "$mgmt_tx" \
		--argjson mgmt_tx_bytes "$mgmt_tx_bytes" \
		--argjson mgmt_rx "$mgmt_rx" \
		--argjson mgmt_rx_bytes "$mgmt_rx_bytes" \
		--argjson forward_pkts "$forward_pkts" \
		--argjson forward_bytes "$forward_bytes" \
		--argjson tx "$tx" \
		--argjson tx_bytes "$tx_bytes" \
		--argjson tx_dropped "$tx_dropped" \
		'{mgmt_tx : $mgmt_tx, mgmt_tx_bytes : $mgmt_tx_bytes, mgmt_rx : $mgmt_rx, mgmt_rx_bytes : $mgmt_rx_bytes, forward_pkts : $forward_pkts , forward_bytes : $forward_bytes, tx : $tx, tx_bytes : $tx_bytes, tx_dropped : $tx_dropped}')
	echo "$jsonout"
}

# Get RSSI per station we're connected with (MAC:dBm)
# TODO do we want average or nah?
function get_every_station_stats_tester()
{
	use_avg=false
	if "$use_avg"; then
		raw=$(iw dev $IW_IFACE station dump | grep "Station\|signal\ avg\|tx packets\|tx retries\|tx failed\|rx packets" | sed 's/signal avg://g')
	else
		raw=$(iw dev $IW_IFACE station dump | grep "Station\|signal\|tx packets\|tx retries\|tx failed\|rx packets" | grep -v "avg\|ack " | sed 's/signal://g')
	fi
	stations=$(echo "$raw" | grep Station | awk '{print $2}')
	for s in $(echo "$stations"); do
		# Print station mac address and its respective signal value
		rssi=$(echo "$raw" | grep $s -A5 | grep dBm | awk '{print $1}')
		tx_retries=$(echo "$raw" | grep $s -A5 | grep retries | awk '{print $3}')
		tx_failed=$(echo "$raw" | grep $s -A5 | grep failed | awk '{print $3}')
		tx_packets=$(echo "$raw" | grep $s -A5 | grep "tx\ packets" | awk '{print $3}')
		rx_packets=$(echo "$raw" | grep $s -A5 | grep "rx\ packets" | awk '{print $3}')
		echo "$s" "$rssi" "$tx_retries" "$tx_failed" "$tx_packets" "$rx_packets"
	done
}

# Basically the above, but more. TODO deprecate the old function _rssi one
function get_every_station_stats()
{
	use_avg=false
	if "$use_avg"; then
		raw=$(iw dev $IW_IFACE station dump | grep "Station\|signal\ avg\|tx packets\|tx retries\|tx failed\|rx packets" | sed 's/signal avg://g')
	else
		raw=$(iw dev $IW_IFACE station dump | grep "Station\|signal\|tx packets\|tx retries\|tx failed\|rx packets" | grep -v "avg\|ack " | sed 's/signal://g')
	fi
	stations=$(echo "$raw" | grep Station | awk '{print $2}')
	for s in $(echo "$stations"); do
		# Print station mac address and its respective signal value
		rssi=$(echo "$raw" | grep $s -A5 | grep dBm | awk '{print $1}')
		tx_retries=$(echo "$raw" | grep $s -A5 | grep retries | awk '{print $3}')
		tx_failed=$(echo "$raw" | grep $s -A5 | grep failed | awk '{print $3}')
		tx_packets=$(echo "$raw" | grep $s -A5 | grep "tx\ packets" | awk '{print $3}')
		rx_packets=$(echo "$raw" | grep $s -A5 | grep "rx\ packets" | awk '{print $3}')
		name=${macs[$s]}
		echo "$s" "$rssi" "$tx_retries" "$tx_failed" "$tx_packets" "$rx_packets"
	done
}

function get_every_station_stats_json()
{
	IFS=$'\n'
	echo "{"
	lines=($(get_every_station_stats))
	out=$(for line in ${lines[@]}; do
		IFS=$'\ '
		line=($line)
		mac=${line[0]}
		name=${macs[$mac]}
		rssi=${line[1]}
		tx_retries=${line[2]}
		tx_failed=${line[3]}
		tx_packets=${line[4]}
		rx_packets=${line[5]}
		noise=$(get_noise_in_use)
		snr=$(($rssi-$noise))
		echo "\"$name\" : {\"rssi\" : $rssi , \"snr\" : $snr , \"tx_retries\" : $tx_retries , \"tx_failed\" : $tx_failed , \"tx_packets\" : $tx_packets , \"rx_packets\" : $rx_packets},"
	done)
	echo "$out" | tr -d '\n' | sed 's/.\{1\}$//' # sed pipe removes trailing comma
	echo "}"
}

# Takes timestamp and iteration parameters to be then put in the json output
# if nothing is passed there, they will be -1
# Looks like the following
# {"timestamp" : -1 , "trial_number" : -1 , "txpower" : 20.00 , "noise" : -91 , "station_dump" : {
# "spitz1" : {"rssi" : -68 , "tx_retries" : 808 , "tx_failed" : 811 , "tx_packets" : 838 , "rx_packets" : 526342},
# "spitz4" : {"rssi" : -88 , "tx_retries" : 45 , "tx_failed" : 46 , "tx_packets" : 38 , "rx_packets" : 389361},
# "spitz2" : {"rssi" : -93 , "tx_retries" : 23 , "tx_failed" : 24 , "tx_packets" : 10 , "rx_packets" : 338411},
# } }
function get_pktloss_rssi_noise_deployment_data()
{
	timestamp="$1"
	trial_number="$2"
	[ -z $timestamp ] && timestamp="-1"
	[ -z $trial_number ] && trial_number="-1"
	noise=$(get_noise_in_use)
	station_dump=$(get_every_station_stats_json)
	batman_stats=$(get_batman_statistics_json)
	txpower=$(get_current_txpower)
	all_tx_packets=$(all_tx_packets)
	sum_per_station_tx_packets=$(sum_per_station_tx_packets)
	echo "{\"timestamp\" : $timestamp , \"trial_number\" : $trial_number , \"txpower\" : $txpower , \"noise\" : $noise , \"all_tx_packets\" : $all_tx_packets, \"sum_per_station_tx_packets\" : $sum_per_station_tx_packets , \"station_dump\" : $station_dump , \"batman_stats\" : $batman_stats}" | tr -d '\n' # tr pipe Removes all newlines
}

# Takes timestamp and iteration parameters to be then put in the json output
# if nothing is passed there, they will be -1
# Looks like the following
# {"timestamp" : -1 , "trial_number" : -1 , "txpower" : 20.00 , "noise" : -91 , "station_dump" : {
# "spitz1" : {"rssi" : -68 , "tx_retries" : 808 , "tx_failed" : 811 , "tx_packets" : 838 , "rx_packets" : 526342},
# "spitz4" : {"rssi" : -88 , "tx_retries" : 45 , "tx_failed" : 46 , "tx_packets" : 38 , "rx_packets" : 389361},
# "spitz2" : {"rssi" : -93 , "tx_retries" : 23 , "tx_failed" : 24 , "tx_packets" : 10 , "rx_packets" : 338411},
# } }
function get_hwmp_pktloss_rssi_noise_deployment_data()
{
	timestamp="$1"
	trial_number="$2"
	[ -z $timestamp ] && timestamp="-1"
	[ -z $trial_number ] && trial_number="-1"
	noise=$(get_noise_in_use)
	station_dump=$(get_every_station_stats_json)
	# batman_stats=$(get_batman_statistics_json)
	txpower=$(get_current_txpower)
	all_tx_packets=$(all_tx_packets)
	sum_per_station_tx_packets=$(sum_per_station_tx_packets)
	echo "{\"timestamp\" : $timestamp , \"trial_number\" : $trial_number , \"txpower\" : $txpower , \"noise\" : $noise , \"all_tx_packets\" : $all_tx_packets, \"sum_per_station_tx_packets\" : $sum_per_station_tx_packets , \"station_dump\" : $station_dump}" | tr -d '\n' # tr pipe Removes all newlines
}

# 
function get_batman_routes()
{
	if [ $1 ]; then # If you pass any argument here, it'll print only the routes
		batctl o | grep -v "adv\|Orig" | sed 's/(//g' | sed 's/)//g' | grep "\*"
	else
		batctl o | grep -v "adv\|Orig" | sed 's/(//g' | sed 's/)//g'
	fi
}

function get_batman_routes_json() # TODO so far this only prints next hop nodes
{
	IFS=$'\n'
	echo "{"
	lines=($(get_batman_routes routes))
	out=$(for line in ${lines[@]}; do
		mac=$(echo $line | awk '{print $2}')
		name=${macs[$mac]}
		score=$(echo $line | awk '{print $4}')
		next_hop=$(echo $line | awk '{print $5}')
		next_hop_name=${macs[$next_hop]}
		# echo "\"$mac\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop"\"},"
		echo "\"$name\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop_name"\"},"
	done)
	echo $out | tr -d '\n' | sed 's/.\{1\}$//' # sed pipe removes trailing comma
	echo "}"
}

function get_hwmp_routes_json()
{
	IFS=$'\n'
	echo "{"
	lines=($(iw dev $IW_IFACE mpath dump | grep -v DEST))
	out=$(for line in ${lines[@]}; do
		mac=$(echo $line | awk '{print $1}')
		name=${macs[$mac]}
		score=$(echo $line | awk '{print $5}')
		next_hop=$(echo $line | awk '{print $2}')
		next_hop_name=${macs[$next_hop]}
		# echo "\"$mac\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop"\"},"
		echo "\"$name\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop_name"\"},"
	done)
	echo $out | tr -d '\n' | sed 's/.\{1\}$//' # sed pipe removes trailing comma
	echo "}"
}

function get_batman_routes_jq() # TODO so far this only prints next hop nodes
{
	IFS=$'\n'
	# echo "{"
	lines=($(get_batman_routes routes))
	for line in ${lines[@]}; do
		mac=$(echo $line | awk '{print $2}')
		name=${macs[$mac]}
		score=$(echo $line | awk '{print $4}')
		next_hop=$(echo $line | awk '{print $5}')
		next_hop_name=${macs[$next_hop]}
		# echo "\"$mac\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop"\"},"
		# echo "\"$name\" : { \"score\" : "$score" , \"next_hop\" : \""$next_hop_name"\"},"
		route_data=$(jq -n \
			--arg name "$name" \
			--argjson score "$score" \
			--arg next_hop "$next_hop_name" \
			'{name: $name , score : $score , next_hop : $next_hop }')
		echo "$route_data"
	done | jq -r
	# echo $out | tr -d '\n' | sed 's/.\{1\}$//' # sed pipe removes trailing comma
	# echo "}"
}

function convert_macs_to_names()
{
	read input
	for mac in ${!macs[@]}; do
		input=$(echo "$input" | sed "s/$mac/${macs[$mac]}/g")
	done
	echo -e "$input"
}
