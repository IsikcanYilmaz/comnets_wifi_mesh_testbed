#!/usr/bin/env bash

DATE_SUFFIX="$(date +%F_%Ih_%Mm)"
RESULTS_DIR=/root/results/prelim_data_gathering_"$HOSTNAME"_"$DATE_SUFFIX"

source "/root/node/collect_feature_data.sh"
mkdir -p $RESULTS_DIR

SLEEP_TIME_S="1"
NUM_TRIALS="5"

case "$1" in
	"--sleep_time")
		shift
		SLEEP_TIME_S="$1"
		shift
		;;
	"--num_trials")
		shift
		NUM_TRIALS="$1"
		shift
		;;
	*)
		shift
		;;
esac

function trial()
{
	get_every_station_rssi
}

echo "[*] $NUM_TRIALS Trials, $SLEEP_TIME_S s Sleep time"

for t in $(seq 0 $(($NUM_TRIALS-1))); do
	echo "- Trial $t"
	trial
	[ $t != $(($NUM_TRIALS-1)) ] && sleep $SLEEP_TIME_S
done
