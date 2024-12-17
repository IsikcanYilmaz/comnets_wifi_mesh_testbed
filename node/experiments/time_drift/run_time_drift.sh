#!/usr/bin/env bash

# TIME DRIFT EXPERIMENT
# Usage: ./run_time_drift.sh <timestamp to start at>
# 

RESULTS_DIR="/root/results/time_drift/time_drift_$(date +%b%d_%Hh_%M)"

NTP_SERVER="pool.ntp.org" # TODO make this a local server

function set_ntp()
{
	# $1: set ntp to 0 or 1
	echo "[*] Setting ntp to $1"
	uci set system.ntp.enabled="$1"
	uci commit system
	/etc/init.d/system restart
	/etc/init.d/sysntpd restart
}

function run()
{
	# $1: number of samples
	# $2: sleep in seconds
	# $3: oneshot
	num_samples=$1
	sleep_s=$2
	results_filename="time_drift_run_"$num_samples"n_"$sleep_s"s.txt"
	echo "[*] Time drift experiment. Num samples: $num_samples, Sleep (s): $sleep_s"
	for i in $(seq 0 $(($num_samples-1))); do
		echo "[*] Sample $i"
		sleep $sleep_s
		ntpdate -q $NTP_SERVER 
	done | tee $RESULTS_DIR/$results_filename
}

function main()
{
	echo "[*] Time drift experiment. General output goes to $RESULTS_DIR"
	set_ntp 1
	ntpdate $NTP_SERVER # Initial sync
	set_ntp 0
	run 3 60 # $((4*16)) $((60*15)) # every 15 minutes, for 16 hours 
	set_ntp 1
	ntpdate $NTP_SERVER # Sync again and leave
	echo "[*] Done!"
}

mkdir -p $RESULTS_DIR
main | tee $RESULTS_DIR/output &
#disown
