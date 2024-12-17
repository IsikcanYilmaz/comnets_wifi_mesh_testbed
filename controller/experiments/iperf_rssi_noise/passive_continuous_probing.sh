#!/usr/bin/env bash

# ./passive_continuous_probing.sh
# We just deployed the routers in the B wing. Now is the time to gather some prelim data and 
# see where we can go. 
#
# Run this from the controller machine. Change some of the hardcoded variables below if needed
#

DATE_SUFFIX="$(date +%F_%Ih_%Mm)"
RESULTS_DIR=results_pktloss_"$DATE_SUFFIX"

IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \#) )

UNAME="root"

# Knobs #
# Default values, 5760 trials with 5 seconds in between, 8 hours
SLEEP_TIME_S="2"

TXPOWER="500" 

DEBUG="" # "echo"
JSON="--json" # for iperf3

function hostname_to_mesh_ip()
{
	hname="$1"
	id=$(echo $hname | sed 's/spitz//g')
	echo 192.168.8.10"$id"
}

# Parse args
while [ $# -gt 0 ]; do
	case "$1" in
		"--debug") # Dry run
			shift
			DEBUG="echo"
			;;
		"--sleep_time") # Seconds to wait inbetween trials
			shift
			SLEEP_TIME_S="$1"
			shift
			;;
		"--name") # Prefix to the results directory name
			shift
			RESULTS_DIR="$1"_"$RESULTS_DIR"
			shift
			;;
		"--txpower") # Tx power 
			shift
			TXPOWER="$1"
			shift
			;;
		*)
			shift
			;;
	esac
done

echo "[*] Results go to $RESULTS_DIR"

# Create subdirs in the results dir for each target
for i in ${targets[@]}; do
	target=$(echo $i | awk '{print $2}')
	targetsubdir="$RESULTS_DIR"/"$target"
	mkdir -p $targetsubdir
	echo $target - $targetsubdir
done

# Note down experiment settings in a file
echo "sleep_time:$SLEEP_TIME_S, txpower:$TXPOWER" > $RESULTS_DIR/.config

echo "[*] Passive probing"
echo "$SLEEP_TIME_S s Sleep time"
echo "Tx Power: $TXPOWER"

#####################################

# First, set tx powers of our targets
for i in ${targets[@]}; do
	# Set txpower while you're at it
	target=$(echo $i | awk '{print $2}')
	$DEBUG ssh $UNAME@$target "iw dev phy0-mesh0 set txpower fixed $TXPOWER"
done

# Run the experiments
t=0
while [ true ] ; do
	tt=$(printf "%06g" $t)
	echo "[*] Trial $t"

	# For every target poll RSSI etc
	local_timestamp=$EPOCHREALTIME
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		ip=$(echo $i | awk '{print $1}')
		$DEBUG ssh $UNAME@$target "source node/collect_feature_data.sh; echo \$EPOCHREALTIME; echo \"-\"; get_every_station_stats; echo \"-\"; get_noise_in_use;" > "$RESULTS_DIR"/"$target"/trial_"$tt"_"$local_timestamp" &
	done

	# Sleep
	sleep $SLEEP_TIME_S
	t=$((t+1))
done

# Kill the iperf3 daemon
$DEBUG ssh $UNAME@$RECEIVER "killall iperf3"

echo "[*] Done!"
