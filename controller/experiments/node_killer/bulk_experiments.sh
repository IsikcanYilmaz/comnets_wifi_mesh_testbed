#!/usr/bin/env bash

MESH_PATH_REFRESH_TIMES=( 100 1000 2000 3000 4000 ) # default 1000
MESH_HWMP_PREQ_MIN_INTERVALS=( 10 100 1000 5000 ) # default 10 ms
MESH_HWMP_MAX_PREQ_RETRIES=( 1 2 3 4 5 6 ) # default 4

OGM_INTERVAL=(100 500 1000 2000 3000 4000 5000 10000)

NUM_LOOPS=10
EXPERIMENT_SCRIPT_PATH=$(realpath continuous_rssi_noise.sh)

function meshtestbed_revive_mesh_radio()
{
	if [ -z "$1" ]; then
		echo "[!] No node given!"	
	else
		# ssh root@"$1" "uci set wireless.radio0.disabled='0'; uci commit wireless; wifi"
		# ssh root@"$1" "ifconfig phy0-mesh0 up; wifi"
		ssh root@"$1" "wifi"
	fi
	# sleep 2
}

function revive_all()
{
	meshtestbed_revive_mesh_radio spitz0 &
	meshtestbed_revive_mesh_radio spitz1 &
	meshtestbed_revive_mesh_radio spitz2 &
	meshtestbed_revive_mesh_radio spitz3 &
	meshtestbed_revive_mesh_radio spitz4 &
	wait $(jobs -p)
	sleep 2
}

function warm_up()
{
	ssh root@spitz0 "ping 192.168.8.101 -c1"
	ssh root@spitz0 "ping 192.168.8.102 -c1"
	ssh root@spitz0 "ping 192.168.8.103 -c1"
	ssh root@spitz0 "ping 192.168.8.104 -c1"
}

function sigint_handler()
{
	echo "[*] Reviving all nodes"
	trap - SIGINT
	revive_all
	echo "[*] Revived all nodes"
	exit 1
}

trap sigint_handler SIGINT

for loop in $(seq 0 $(($NUM_LOOPS-1))); do
	echo "[*] LOOP $loop"
	mkdir -p batman_sweep_"$loop"
	cd ping_hwmp_sweep_"$loop"

	ctr=0
	for mesh_path_refresh_time in ${MESH_PATH_REFRESH_TIMES[@]}; do
		for mesh_hwmp_preq_min_interval in ${MESH_HWMP_PREQ_MIN_INTERVALS[@]}; do
			for mesh_hwmp_max_preq_retries in ${MESH_HWMP_MAX_PREQ_RETRIES[@]}; do

				echo "[*] Path refresh time: $mesh_path_refresh_time, Preq min interval $mesh_hwmp_preq_min_interval, Max preq retries $mesh_hwmp_max_preq_retries"

				name=$ctr"_refresh_"$mesh_path_refresh_time"_mininterval_"$mesh_hwmp_preq_min_interval"_preqretries_"$mesh_hwmp_max_preq_retries

				[ "$(ls | grep "$name")" != "" ] && continue # already exists

				# warm_up
				
				# Timed
				../continuous_rssi_noise.sh --name "$name" --hwmp --bitrate 1M --txpower 1500 --run_time 60 --poll_period 5 --node_kill_at 20 --mesh_path_refresh_time $mesh_path_refresh_time --mesh_hwmp_preq_min_interval $mesh_hwmp_preq_min_interval --mesh_hwmp_max_preq_retries $mesh_hwmp_max_preq_retries
			
				# Payload
				# ../continuous_rssi_noise.sh --name "$name" --hwmp --bitrate 1M --payload_mode --txpower 1200 --node_kill_at 10 --pcap --mesh_path_refresh_time $mesh_path_refresh_time --mesh_hwmp_preq_min_interval $mesh_hwmp_preq_min_interval --mesh_hwmp_max_preq_retries $mesh_hwmp_max_preq_retries

				# Ping
				# ../continuous_rssi_noise.sh --name "$name" --hwmp --txpower 1000 --node_kill_at 20 --run_time 40 --ping --no_iperf --pcap --mesh_path_refresh_time $mesh_path_refresh_time --mesh_hwmp_preq_min_interval $mesh_hwmp_preq_min_interval --mesh_hwmp_max_preq_retries $mesh_hwmp_max_preq_retries

				revive_all
				
				sleep 5
				ctr=$(($ctr+1))
			done
		done
	done

	# cd ..
done
