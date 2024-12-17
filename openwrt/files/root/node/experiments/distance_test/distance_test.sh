#!/usr/bin/env bash

helptext='''
Usage: ./distance_test.sh <distance>\n

Have Spitz1 transmit to Spitz2 at different txpower values.\n

Sweep tx power and bandwidth. The point is to see tx power and bandwidth limits while the routers are apart by varying distances.\n

This script should reside in the transmitter machine.\n

Pass the current distance as the argument to have it in the results file name. \n

'''

TRANSMITTER_IP="192.168.4.111"
RECEIVER_IP="192.168.4.112"

# Default idea is to have spitz1(the access point) wail on spitz2(the station)
TRANSMITTER_IFACE="phy0-ap0"
RECEIVER_IFACE="phy0-sta0"

UNAME="root"

TX_SWEEP_BASE=100 # 10.0 dB
TX_SWEEP_INCREMENT=100 
TX_SWEEP_UPPER_LIMIT=2100

BW_SWEEP_BASE=100 # 100 Mbps
BW_SWEEP_INCREMENT=100
BW_SWEEP_UPPER_LIMIT=300

SAMPLE_TIME_S=5 # Run iperf for this many seconds

DATE_SUFFIX="$(date +%F_%Ih)"
RESULTS_DIR="/root/results/distance_test/$DATE_SUFFIX/"

JSON="--json"

DISTANCE="$1"

mkdir -p $RESULTS_DIR
echo "[*] Distance test writing results to $RESULTS_DIR"

tx=$TX_SWEEP_BASE
while [ "$tx" -lt "$TX_SWEEP_UPPER_LIMIT" ]; do
	bw=$BW_SWEEP_BASE
	while [ "$bw" -lt "$BW_SWEEP_UPPER_LIMIT" ]; do
		echo "BW $bw TX $tx"

		# Set remote machine's tx power
		ssh $UNAME@$RECEIVER_IP "iw $RECEIVER_IFACE set txpower fixed $tx"

		# Set our tx power
		iw $TRANSMITTER_IFACE set txpower fixed $tx
		iw dev

		# Run iperf3 on target machine
		ssh $UNAME@$RECEIVER_IP "iperf3 -D -s -1"

		# Run iperf3 on our machine
		iperf3 -u -c $RECEIVER_IP -b "$bw"M -t $SAMPLE_TIME_S $JSON | tee $RESULTS_DIR/bw_"$bw"_tx_"$tx"_distance_"$DISTANCE".txt
		
		bw=$(($bw + $BW_SWEEP_INCREMENT))

		# break
	done

	# Get rssi
	iw dev $TRANSMITTER_IFACE station dump | tee $RESULTS_DIR/tx_"$tx"_dist_"$DISTANCE"_sta_dump.txt

	tx=$(($tx + $TX_SWEEP_INCREMENT))
	
	# break
done


echo "[*] Distance: $DISTANCE Done!"
