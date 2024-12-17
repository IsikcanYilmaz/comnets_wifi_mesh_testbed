#!/usr/bin/env bash

# ./pktloss_rssi_noise_deployment.sh
# We just deployed the routers in the C wing. Now is the time to gather some data and 
# see where we can go. 
#
# Run this from the controller machine. Change some of the hardcoded variables below if needed
#

DATE_SUFFIX="$(date +%F_%Ih_%Mm)"
RESULTS_DIR=results_pktloss_"$DATE_SUFFIX"

MONGO=false # TODO decide if you want mongo on by default
MONGO_DB="network_tests_$DATE_SUFFIX"
MONGO_HOST="localhost"
MONGO_PORT="27017"
MONGO_COLLECTION="results"

CMDLINE=$(printf %q "$BASH_SOURCE")$((($#)) && printf ' %q' "$@")

IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \# | grep -v testbed | grep -v localhost) )
tx_boxes=( $(cat /etc/hosts | grep nuc) )

UNAME="root"

NUC_UNAME="jon"

# Knobs #
# Default values, 5760 trials with 5 seconds in between, 8 hours
SLEEP_TIME_S="0"
NUM_TRIALS="5760"

# Default values 355KB payload, which is the size of a png in the SLAM euroc dataset
# 10 images at 5 Mbps
IPERF=true
SINGLE_PAYLOAD_SIZE="355" # Kbps 
NUM_PAYLOADS="1"
PAYLOAD_SIZE="$(($NUM_PAYLOADS * $SINGLE_PAYLOAD_SIZE))"K
BITRATE="10M"
BITRATE_SWEEP=false
BITRATE_SWEEP_NUM_TRIALS=100
BITRATE_SWEEP_INCREMENT="1M"
BITRATE_SWEEP_INCREMENT_UNTIL="1000M"

TRANSMITTER="spitz3"
TRANSMITTER_IP="192.168.8.103"
RECEIVER="spitz1"
RECEIVER_IP="192.168.8.101"
NUC_TRANSMITTER=false

TXPOWER="1500" 
RANDOM_TXPOWER=false
RANDOM_TXPOWER_NUM_TRIALS=100
TXPOWER_LL="1200" 
TXPOWER_UL="2000"
ROUTER_TXPOWER=()

OGM_INTERVAL="100" # BATMAN originator message interval
OGM_INTERVAL_SWEEP=false
OGM_INTERVAL_SWEEP_INCREMENT="100"
OGM_INTERVAL_SWEEP_NUM_TRIALS="100"

HWMP=false

ERROR_COUNT=3

ALL_TO_ONE=false

CONSOLIDATOR=true

DEBUG="" # "echo"
JSON="--json" # for iperf3

function hostname_to_mesh_ip() # TODO unused. remove
{
	hname="$1"
	id=$(echo $hname | sed 's/spitz//g')
	echo 192.168.8.10"$id"
}

# set_txpowers sets tx powers of all routers to $1. if $1 is not passed, a random number is picked between
# $TXPOWER_LL and $TXPOWER_UL
function set_txpowers()
{
	txpower_ul=$(($TXPOWER_UL / 100)) # shuf the random number gen takes numbers between 5 and 20
	txpower_ll=$(($TXPOWER_LL / 100)) 
	for i in ${targets[@]}; do
		if [ -z "$1" ]; then # if nothing is passed
			txpower=$(shuf -i "$txpower_ll"-"$txpower_ul" -n 1)
			txpower="${txpower}00"
		else # if something is passed
			txpower="$1"
		fi
		# Set txpower while you're at it
		target=$(echo $i | awk '{print $2}')
		[ $DEBUG ] && echo "Setting $target tx power to $txpower"
		$DEBUG ssh $UNAME@$target "iw dev phy0-mesh0 set txpower fixed $txpower" &
	done
	# Wait for ssh cmds
	wait $(jobs -p)
}

# Set router specific txpower
# $1 router name "spitz0" etc.
# $2 txpower
function set_router_txpower()
{
	target="$1"
	txpower="$2"
	echo "Setting $target txpower to $txpower"
	$DEBUG ssh $UNAME@$target "iw dev phy0-mesh0 set txpower fixed $txpower"
}

# Set originator message interval in ms. $1 is ogm interval ms
function set_ogm_interval()
{
	if [ !"$HWMP" ]; then 
		return
	fi
	ogmInterval="$1"
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		[ $DEBUG ] && echo "Setting $target ogm interval $ogmInterval"
		$DEBUG ssh $UNAME@$target "batctl it $ogmInterval" &
	done
	# Wait for ssh cmds
	wait $(jobs -p)
}

# Save data file to mongo
function save_to_mongo() {
  local data_file="$1"
  local collection="$2"
  if [ -z "$collection" ]; then
    echo "Error: Collection name is empty"
    return
  fi
  echo "Saving $data_file to MongoDB collection: $collection"
  python3 - <<END
import sys
import json
from pymongo import MongoClient

data_file = "$data_file"
collection = "$collection"

try:
    with open(data_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error loading JSON data from $data_file: {e}")
    sys.exit(1)

client = MongoClient("$MONGO_HOST", $MONGO_PORT)
db = client["$MONGO_DB"]
coll = db[collection]

try:
    coll.insert_one(data)
except Exception as e:
    print(f"Error inserting data into MongoDB collection $collection: {e}")
    sys.exit(1)
END
}

# Start iperf3 daemon on $RECEIVER
function kill_iperf3()
{
	$DEBUG ssh $UNAME@$RECEIVER "killall iperf3" > /dev/null 2>&1 
	$DEBUG ssh $UNAME@$TRANSMITTER "killall iperf3" > /dev/null 2>&1 
}

function start_iperf3()
{
	# In case iperf was active from before
	# $DEBUG ssh $UNAME@$RECEIVER "killall iperf3" > /dev/null 2>&1 &
	# $DEBUG ssh $UNAME@$TRANSMITTER "killall iperf3" > /dev/null 2>&1 &

	if [ "$ALL_TO_ONE" == true ]; then
		# If it's all to one, run iperf3 server with port 999$id where $id is the intended transmitter's id (i.e. 0 for spitz0)
		for i in ${targets[@]}; do
			target=$(echo $i | awk '{print $2}')
			[ "$target" == "$RECEIVER" ] && continue
			id=$(echo $target | sed 's/spitz//g')
			port="999"$id
			$DEBUG ssh $UNAME@$RECEIVER "iperf3 -D -s B $RECEIVER_IP -p $port" &
		done
	else
		# If it's a single tx single rx situation, just run the iperf3 daemon on the rx
		$DEBUG ssh $UNAME@$RECEIVER "iperf3 -D -s -B $RECEIVER_IP" &
	fi
	wait $(jobs -p)
}

###########################################################
# Parse args
while [ $# -gt 0 ]; do
	case "$1" in
		"--all_to_one") # Instead of a one on one connetion, have all spitzs send iperf traffic to $RECEIVER
			shift
			ALL_TO_ONE=true
			;;
		"--debug") # Dry run
			shift
			DEBUG="echo"
			;;
		"--sleep") # Seconds to wait inbetween trials
			shift
			SLEEP_TIME_S="$1"
			shift
			;;
		"--num_trials") # Number of trials to run
			shift
			NUM_TRIALS="$1"
			shift
			;;
		"--name") # Prefix to the results directory name
			shift
			RESULTS_DIR="$1"_"$RESULTS_DIR"
			MONGO_DB="$1"_"$MONGO_DB"
			shift
			;;
		"--full_name") # Override the name completely
			shift
			RESULTS_DIR="$1"
			MONGO_DB="$1"
			shift
			;;
		"--payload_size") # Size of payload to be sent over iperf
			shift
			PAYLOAD_SIZE="$1"
			shift
			;;
		"--txpower") # Tx power (in case we do random tx powers, this is the initial tx power that everyone starts at)
			shift
			TXPOWER="$1"
			shift
			;;
		"--random_txpower") # Tx power of all routers get randomized thruout the experiment
			shift
			RANDOM_TXPOWER=true
			;;
		"--random_txpower_num_trials") # num trials to spend on each random tx power value
			shift
			NUM_TRIALS_PER_RANDOM_TXPOWER="$1"
			shift
			;;
		"--router_txpower") # Set specific router's tx power. arguments are like --router_txpower "spitz0 2000"
			shift
			ROUTER_TXPOWER+=("$1")
			shift
			;;
		"--mongo") # Disable saving to mongo database
			shift
			MONGO=true
			;;
		"--no_iperf") # Dont run iperf
			shift
			IPERF=false
			;;
		"--no_consolidator") # Do not consolidate
			shift
			CONSOLIDATOR=false
			;;
		"--nuc_tx") # Use nuc0 as the transmitter
			shift
			NUC_TRANSMITTER=true # TODO make more generic
			TRANSMITTER="nuc0"
			TRANSMITTER_IP=$(cat /etc/hosts | grep $TRANSMITTER | awk '{print $1}')
			;;
		"--bitrate") # Set iperf bitrate
			shift
			BITRATE="$1"
			shift
			;;
		"--bitrate_sweep") # Run bitrate sweep routine
			shift
			BITRATE_SWEEP=true
			;;
		"--bitrate_sweep_num_trials") # Increment bitrate every $this number of trials
			shift
			BITRATE_SWEEP_NUM_TRIALS="$1"
			shift
			;;
		"--bitrate_sweep_increment") # Increment bitrate by
			shift
			BITRATE_SWEEP_INCREMENT="$1"
			shift
			;;
		"--bitrate_sweep_increment_until") # Increment bitrate until this value
			shift
			BITRATE_SWEEP_INCREMENT_UNTIL="$1"
			shift
			;;
		"--ogm_interval") # BATMAN Originator message interval in ms
			shift
			OGM_INTERVAL="$1"
			shift
			;;
		"--ogm_interval_sweep") # Run ogm_interval sweep routine
			shift
			OGM_INTERVAL_SWEEP=true
			;;
		"--ogm_interval_sweep_num_trials") # Increment ogm_interval every $this number of trials
			shift
			OGM_INTERVAL_SWEEP_NUM_TRIALS="$1"
			shift
			;;
		"--ogm_interval_sweep_increment") # Increment ogm_interval by
			shift
			OGM_INTERVAL_SWEEP_INCREMENT="$1"
			shift
			;;
		"--exclude_node") # Exclude this node from ssh commands
			shift
			excludeStr="$excludeStr $1"
			shift
			;;
		"--hwmp") # Use hwmp tooling
			echo "[*] Using HWMP"
			HWMP=true
			shift
			;;
		*)
			echo "[!] Error: Bad argument! $1"
			exit
			shift
			;;
	esac
done

echo "[*] Results go to $RESULTS_DIR"

declare -a IPERF_DIRS
declare -a STATION_DIRS

# Let's deal with numbers instead of strings. 
# Convert Ms to 000000 and Ks to 000 for iperf bitrate values
BITRATE=$(echo $BITRATE | sed 's/M/000000/g' | sed 's/K/000/g')
BITRATE_SWEEP_INCREMENT=$(echo $BITRATE_SWEEP_INCREMENT | sed 's/M/000000/g' | sed 's/K/000/g')
BITRATE_SWEEP_INCREMENT_UNTIL=$(echo $BITRATE_SWEEP_INCREMENT_UNTIL | sed 's/M/000000/g' | sed 's/K/000/g')

# If this run excludes some nodes, remove them from the $targets array
if [ "$excludeStr" ]; then
	filteredtargets=$(for i in ${targets[@]}; do 
		target=$(echo $i | awk '{print $2}');
		if [[ ! "$excludeStr" =~ "$target" ]]; then
			echo $i 
		fi
	done)
	unset targets
	targets="$filteredtargets"
	echo "[*] Only using the following targets:" ${targets[@]}
fi

# Create subdirs in the results dir for each target
for i in ${targets[@]}; do
	target=$(echo $i | awk '{print $2}')
	targetsubdir="$RESULTS_DIR"/"$target"
	mkdir -p $targetsubdir
	echo $target - $targetsubdir
	STATION_DIRS+=("$RESULTS_DIR"/"$target")
done

# Create subdir for our iperf pairs
IPERF_RESULTS_DIR="$RESULTS_DIR"/iperf_"$TRANSMITTER"_"$RECEIVER"
if [ "$IPERF" == true ]; then
	if [ "$ALL_TO_ONE" != true ]; then
		mkdir -p $IPERF_RESULTS_DIR
		echo "iperf $IPERF_RESULTS_DIR"
		IPERF_DIRS+=("$RESULTS_DIR"/"iperf_"$target"_"$RECEIVER)
	else
		for i in ${targets[@]}; do
			target=$(echo $i | awk '{print $2}')
			[ "$target" == "$RECEIVER" ] && continue
			mkdir -p "$RESULTS_DIR"/iperf_"$target"_"$RECEIVER"
			echo "iperf $RESULTS_DIR"/iperf_"$target"_"$RECEIVER"
			IPERF_DIRS+=("$RESULTS_DIR"/"iperf_"$target"_"$RECEIVER)
		done
	fi
fi

# Create subdir for consolidated json files
mkdir -p "$RESULTS_DIR"/consolidated

# Note down experiment settings in a file
config_data=$(jq -n \
	--arg num_trials "$NUM_TRIALS" \
	--arg sleep_time "$SLEEP_TIME_S" \
	--arg txpower "$TXPOWER" \
	--arg payload "$PAYLOAD_SIZE" \
	--arg tx "$TRANSMITTER" \
	--arg rx "$RECEIVER" \
	--argjson a2o "$ALL_TO_ONE" \
	--argjson randtx "$RANDOM_TXPOWER" \
	--arg randtx_numtrials "$NUM_TRIALS_PER_RANDOM_TXPOWER" \
	--arg bitrate "$BITRATE" \
	--argjson bitrate_sweep "$BITRATE_SWEEP" \
	--arg bitrate_sweep_increment "$BITRATE_SWEEP_INCREMENT" \
	--arg bitrate_sweep_num_trials "$BITRATE_SWEEP_NUM_TRIALS" \
	--arg bitrate_sweep_increment_until "$BITRATE_SWEEP_INCREMENT_UNTIL" \
	--arg ogm_interval "$OGM_INTERVAL" \
	--argjson ogm_interval_sweep "$OGM_INTERVAL_SWEEP" \
	--arg ogm_interval_sweep_increment "$OGM_INTERVAL_SWEEP_INCREMENT" \
	--arg ogm_interval_sweep_num_trials "$OGM_INTERVAL_SWEEP_NUM_TRIALS" \
	--argjson hwmp "$HWMP" \
	--arg cmdline "$CMDLINE" \
	'{num_trials: $num_trials, sleep_time: $sleep_time, txpower: $txpower, payload: $payload, bitrate: $bitrate, bitrate_sweep: $bitrate_sweep, bitrate_sweep_num_trials: $bitrate_sweep_num_trials, bitrate_sweep_increment: $bitrate_sweep_increment, bitrate_sweep_increment_until: $bitrate_sweep_increment_until, ogm_interval: $ogm_interval, ogm_interval_sweep: $ogm_interval_sweep, ogm_interval_sweep_increment: $ogm_interval_sweep_increment, ogm_interval_sweep_num_trials: $ogm_interval_sweep_num_trials, tx: $tx, rx: $rx, a2o: $a2o, randtx: $randtx, randtx_numtrials: $randtx_numtrials, hwmp: $hwmp, cmdline: $cmdline}')
echo "$config_data" > "$RESULTS_DIR"/.config

if [ "$MONGO" == true ]; then 
	echo "[*] MongoDB database: $MONGO_DB"
	$DEBUG save_to_mongo "$RESULTS_DIR/.config" "config" 
fi

echo "[*] Experiment configuration:"
cat "$RESULTS_DIR"/.config 

##################################################################################

# First, set tx powers of our targets to our initial txpower
set_txpowers $TXPOWER

# set -x

# Then, if we have any specific router txpowers, set them too
echo "ROUTER TXPOWER LEN ${#ROUTER_TXPOWER[@]}"
for i in $(seq 0 $((${#ROUTER_TXPOWER[@]}-1))) ; do
	router=$(echo ${ROUTER_TXPOWER[$i]} | awk '{print $1}')
	txpower=$(echo ${ROUTER_TXPOWER[$i]} | awk '{print $2}')
	set_router_txpower "$router" "$txpower" 
done

# Set OGM interval
set_ogm_interval $OGM_INTERVAL

# Run iperf3 daemon on the target machine ########################################
if [ "$IPERF" == true ] ; then
	# kill_iperf3
	start_iperf3
fi

# Run the experiments #############################################################
for t in $(seq 0 $(($NUM_TRIALS-1))); do
	tt=$(printf "%06g" $t) # Trial number with padding 0s
	echo "[*] Trial $t / $NUM_TRIALS" $(date)

	# Chaos #########################################################################
	# If this is a random txpower run, check if we have to randomize
	if [ "$RANDOM_TXPOWER" == true ] && [ $t -gt 0 ] && [ $(($t % $NUM_TRIALS_PER_RANDOM_TXPOWER)) -eq 0 ]; then
		echo "Randomizing tx powers at trial $t"
		set_txpowers
	fi

	# If this is a bitrate sweep run, check if it's time to increment
	if [ "$BITRATE_SWEEP" == true ] && [ $t -gt 0 ] && [ $(($t % $BITRATE_SWEEP_NUM_TRIALS)) -eq 0 ] && [ "$BITRATE" -lt "$BITRATE_SWEEP_INCREMENT_UNTIL" ] ; then
		BITRATE=$(($BITRATE + $BITRATE_SWEEP_INCREMENT))
		echo "Incrementing bitrate. New Bitrate $BITRATE"
	fi

	# If this is a ogm interval sweep run, check if it's time to increment
	if [ "$OGM_INTERVAL_SWEEP" == true ] && [ $t -gt 0 ] && [ $(($t % $OGM_INTERVAL_SWEEP_NUM_TRIALS)) -eq 0 ]; then
		OGM_INTERVAL=$(($OGM_INTERVAL + $OGM_INTERVAL_SWEEP_INCREMENT))
		set_ogm_interval $OGM_INTERVAL
		echo "Incrementing ogm interval. New ogm interval $OGM_INTERVAL"
	fi

	#################################################################################
	# For every target poll RSSI and batman routes ##################################
	local_timestamp=$(echo $EPOCHREALTIME | sed 's/,/./g')
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		ip=$(echo $i | awk '{print $1}')
		if [ "$HWMP" ]; then
			$DEBUG ssh $UNAME@$target "source node/collect_feature_data.sh; get_hwmp_pktloss_rssi_noise_deployment_data $local_timestamp $t" > "$RESULTS_DIR"/"$target"/stationdump_"$tt".json &
			$DEBUG ssh $UNAME@$target "source node/collect_feature_data.sh; get_hwmp_routes_json" > "$RESULTS_DIR"/"$target"/routes_"$tt".json &
		else
			$DEBUG ssh $UNAME@$target "source node/collect_feature_data.sh; get_pktloss_rssi_noise_deployment_data $local_timestamp $t" > "$RESULTS_DIR"/"$target"/stationdump_"$tt".json &
			$DEBUG ssh $UNAME@$target "source node/collect_feature_data.sh; get_batman_routes_json" > "$RESULTS_DIR"/"$target"/routes_"$tt".json &
		fi
	done

	# Wait for backgrounded RSSI gathering jobs
	wait $(jobs -p)

	# Once RSSI jobs are complete you can save the output to mongo if needed
	if [ "$MONGO" == true ]; then
		for i in ${targets[@]}; do
			target=$(echo $i | awk '{print $2}')
			($DEBUG save_to_mongo "$RESULTS_DIR"/"$target"/stationdump_"$tt".json "$target" &)
		done
	fi

	#################################################################################
	# Run iperf on transmitter ######################################################
	if [ "$IPERF" == true ]; then

		# NOTE: https://github.com/esnet/iperf/issues/862#issuecomment-490292958
		# iperf3 has an issue where if the very first UDP packet doesnt make it through, the whole run fails
		# my workaround is a retry mechanism; if the outputted json file has an "error" field, retry the run

		# There are times where the previous iperf3 run doesnt realize it ended. kill it and restart it
		kill_iperf3
		start_iperf3

		# ALL TO ONE ####################################################################
		if [ "$ALL_TO_ONE" == true ]; then
			# If this is an all to one situation: go thru each target and have it run iperf to $RECEIVER
			for transmitterEntry in ${targets[@]}; do
				transmitter=$(echo $transmitterEntry | awk '{print $2}')
				[ "$transmitter" == "$RECEIVER" ] && continue 
				id=$(echo $transmitter | sed 's/spitz//g')
				port="999"$id
				$DEBUG ssh $UNAME@$transmitter "iperf3 -u -c $RECEIVER_IP -n $PAYLOAD_SIZE -p $port -b $BITRATE $JSON" | jq --argjson timestamp $local_timestamp --arg transmitter $transmitter --arg receiver $RECEIVER '.timestamp = $timestamp | .transmitter = $transmitter | .receiver = $receiver' > $RESULTS_DIR/iperf_"$transmitter"_"$RECEIVER"/iperf_"$tt".json &
			done

			# Wait for backgrounded iperf jobs
			wait $(jobs -p)

			# Save to mongo if needed  # TODO do the error checking here too
			if [ "$MONGO" == true ]; then
				for transmitterEntry in ${targets[@]}; do
					transmitter=$(echo $transmitterEntry | awk '{print $2}')
					[ "$transmitter" == "$RECEIVER" ] && continue
					($DEBUG save_to_mongo "$RESULTS_DIR"/iperf_"$transmitter"_"$RECEIVER"/iperf_"$tt".json iperf_"$transmitter"_"$RECEIVER" &)
				done
			fi

		# SINGLE TRANSMITTER #############################################################
		else
			error_retry_count=0
			while [ "$error_retry_count" -lt $ERROR_COUNT ]; do
				# If this is a single transmitter single receiver situation, just run iperf on the transmitter
				$DEBUG timeout 60s ssh $UNAME@$TRANSMITTER "iperf3 --connect-timeout 10000 -u -c $RECEIVER_IP -n $PAYLOAD_SIZE -b $BITRATE $JSON" | jq --argjson timestamp $local_timestamp --arg transmitter $TRANSMITTER --arg receiver $RECEIVER '.timestamp = $timestamp | .transmitter = $transmitter | .receiver = $receiver' > "$IPERF_RESULTS_DIR"/iperf_"$tt".json

				# Check for errors. If errored, retry run
				if [ "$(cat "$IPERF_RESULTS_DIR"/iperf_"$tt".json | jq '.error')" == "null" ]; then
					# No errors
					break
				else
					# Errors
					echo "Iperf run $tt errored. Retrying $error_retry_count"
					error_retry_count=$(($error_retry_count + 1))
					kill_iperf3
					start_iperf3
				fi
			done

			# Save to mongo if needed 
			[ "$MONGO" == true ] && ($DEBUG save_to_mongo "$IPERF_RESULTS_DIR"/iperf_"$tt".json iperf_"$TRANSMITTER"_"$RECEIVER" &)
		fi
	fi
	###################################################################################
	
	###################################################################################
	# Generate consolidated json file. This will include the results from each router and each iperf run on this iteration
	if [ -z $DEBUG ] && [ "$CONSOLIDATOR" == true ]; then
		./consolidator.sh "$RESULTS_DIR" "$t" "$local_timestamp" &
	fi

	###################################################################################
	# Sleep
	[ $t -lt $(($NUM_TRIALS-1)) ] && sleep $SLEEP_TIME_S
done

# Kill the iperf3 daemon
[ "$IPERF" == true ] && $DEBUG ssh $UNAME@$RECEIVER "killall iperf3" && $DEBUG ssh $UNAME@$TRANSMITTER "killall iperf3"

# Tar the results for easy transport
tar zcvf "$RESULTS_DIR".tar $RESULTS_DIR &> /dev/null

echo "[*] Done!"
