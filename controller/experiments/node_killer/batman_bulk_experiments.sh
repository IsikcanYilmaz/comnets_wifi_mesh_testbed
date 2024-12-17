#!/usr/bin/env bash

OGMS=( 100 500 1000 2000 3000 4000 5000 6000 7000 8000 9000 10000 )
TXS=( 1500 )
NUM_LOOPS=20
EXPERIMENT_SCRIPT_PATH=$(realpath continuous_rssi_noise.sh)

IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \# | grep -v testbed | grep -v localhost) )
tx_boxes=( $(cat /etc/hosts | grep nuc) )

function meshtestbed_revive_mesh_radio()
{
	if [ -z "$1" ]; then
		echo "[!] No node given!"	
	else
		# ssh root@"$1" "uci set wireless.radio0.disabled='0'; uci commit wireless; wifi"
		# ssh root@"$1" "ifconfig phy0-mesh0 up; wifi"
		ssh root@"$1" "wifi up"
	fi
	sleep 2
}

function sigint_handler()
{
	echo "[*] Reviving all nodes"
	trap - SIGINT
	meshtestbed_revive_mesh_radio spitz0
	meshtestbed_revive_mesh_radio spitz1
	meshtestbed_revive_mesh_radio spitz2
	meshtestbed_revive_mesh_radio spitz3
	meshtestbed_revive_mesh_radio spitz4
	echo "[*] Revived all nodes"
	exit 1
}

function warmup()
{
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		ssh root@"$target" "killall iperf3"
	done
}

trap sigint_handler SIGINT

for loop in $(seq 0 $(($NUM_LOOPS-1))); do
	echo "[*] LOOP $loop"
	dirname="120_s_blank_wcnc_sweep_$loop"
	mkdir -p $dirname 
	cd $dirname 
	for tx in ${TXS[@]}; do
		for ogm in ${OGMS[@]}; do
			echo "[*] OGM $ogm TX $tx RUN"
			name="$ogm"_ogm_"$tx"_tx
			if [ -z "$(ls | grep $name)" ]; then
				# bash $EXPERIMENT_SCRIPT_PATH --name "$name" --txpower $tx --batman --node_kill_at 20 --run_time 60 --ogm_interval $ogm --bitrate 1M --pcap
				warmup
				# bash $EXPERIMENT_SCRIPT_PATH --name "$name" --txpower $tx --batman --node_kill_at 10 --ogm_interval $ogm --payload_mode --bitrate 10M 
				bash $EXPERIMENT_SCRIPT_PATH --name "$name" --txpower $tx --batman --node_kill_at 10 --ogm_interval $ogm --payload_mode --bitrate 10M --blank --run_time 120
				# bash $EXPERIMENT_SCRIPT_PATH --name "$name" --txpower $tx --batman --node_kill_at 20 --run_time 60 --ogm_interval $ogm 
				sleep 5
				echo "[*] ~~~~~~~~~~~~~~~ RUN COMPLETE ~~~~~~~~~~~~~~~~~"
			else
				echo "[*] $name already exists"
			fi
		done
	done
	cd ..
done
