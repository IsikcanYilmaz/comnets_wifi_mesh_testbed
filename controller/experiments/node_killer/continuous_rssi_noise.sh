#!/usr/bin/env bash

DATE_SUFFIX="$(date +%F_%Ih_%Mm)"
RESULTS_DIR=results_continuous_pktloss_"$DATE_SUFFIX"

CMDLINE=$(printf %q "$BASH_SOURCE")$((($#)) && printf ' %q' "$@")

IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \# | grep -v testbed | grep -v localhost) )
tx_boxes=( $(cat /etc/hosts | grep nuc) )

UNAME="root"

NUC_UNAME="jon"

# Knobs #
# Default values, 5760 trials with 5 seconds in between, 8 hours
POLL_PERIOD="1" # Seconds? 
RUN_TIME="30" # Seconds

# Default values 355KB payload, which is the size of a png in the SLAM euroc dataset
# 10 images at 5 Mbps
IPERF=true
BITRATE="1M"
BITRATE_SWEEP=false
BITRATE_SWEEP_NUM_TRIALS=100
BITRATE_SWEEP_INCREMENT="1M"
BITRATE_SWEEP_INCREMENT_UNTIL="1000M"

PING=false
BLANK=false

PAYLOAD_MODE=false # In payload mode we send a payload. otherwise we run for a time
PAYLOAD_SIZE=20M

TRANSMITTER="spitz0"
TRANSMITTER_IP="192.168.8.100"
RECEIVER="spitz3"
RECEIVER_IP="192.168.8.103"
NUC_TRANSMITTER=false

TXPOWER="2000" 
RANDOM_TXPOWER=false
RANDOM_TXPOWER_NUM_TRIALS=100
TXPOWER_LL="1000" 
TXPOWER_UL="2000"
ROUTER_TXPOWER=()

OGM_INTERVAL="100" # BATMAN originator message interval
OGM_INTERVAL_SWEEP=false
OGM_INTERVAL_SWEEP_INCREMENT="100"
OGM_INTERVAL_SWEEP_NUM_TRIALS="100"

NODE_KILL_AT="0" # After this many seconds into the experiment, start running the node killer procedure 

HWMP=false
BATMAN=true

PCAP=false
filterStr=""
macPrefix="94:83:C4:A0:00"

ERROR_COUNT=3

ALL_TO_ONE=false

CONSOLIDATOR=true

DEBUG="" # "echo"
JSON="--json" # for iperf3

# hwmp params
mesh_path_refresh_time="10000"
mesh_hwmp_preq_min_interval="10000"
mesh_hwmp_max_preq_retries="10"
mesh_hwmp_active_path_timeout="10000"

function json_consolidator()
{
	cd $1 # results dir
	fields=( mgmt_tx mgmt_tx_bytes mgmt_rx mgmt_rx_bytes forward_pkts forward_bytes tx tx_bytes tx_dropped )
	# Produce delta jsons
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
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
	cat total_batman_stats.json
	cd -
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

function revive_all()
{
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		$DEBUG ssh $UNAME@$target "wifi ; batctl it 100" &
	done
	# Wait for ssh cmds
	wait $(jobs -p)
	sleep 10
}

# Set originator message interval in ms. $1 is ogm interval ms
function set_ogm_interval()
{
	ogmInterval="$1"
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		echo "Setting $target ogm interval $ogmInterval"
		$DEBUG ssh $UNAME@$target "batctl it $ogmInterval" &
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


# Start iperf3 daemon on $RECEIVER
function kill_iperf3()
{
	$DEBUG ssh $UNAME@$RECEIVER "killall iperf3" > /dev/null 2>&1 
	$DEBUG ssh $UNAME@$TRANSMITTER "killall iperf3" > /dev/null 2>&1 
}

# $1: source $2: destination hostnames
# returns path from $1 to $2
# BATMAN
function meshtestbed_batman_get_route()
{
	a="$1"
	b="$2"
	if [ -z "$a" ] || [ -z "$b" ]; then
		echo "{\"error\":\"Bad arguments\"}"
		return
	fi
	path=( "\"$a\"" )
	next_hop=""
	while [ "$next_hop" != "$b" ]; do
		next_hop=$(ssh root@$a "source /root/node/collect_feature_data.sh; get_batman_routes_json | jq .$b.next_hop" | sed 's/\"//g')
		if [ -z "$next_hop" ] || [ "$next_hop" == "null" ]; then
			echo "{\"error\":\"Routes command returned $next_hop\"}"
			return
		fi
		path+=( \"$next_hop\" )
		a="$next_hop"
	done
	raw=$(echo \["${path[@]}"\] | sed 's/ /,/g')
	jq -n --argjson route "$raw" --arg from "$1" --arg to "$2" '{route:$route, from: $from, to: $to}'
}

# Same args as above
# HWMP
function meshtestbed_hwmp_get_route()
{
	a="$1"
	b="$2"
	if [ -z "$a" ] || [ -z "$b" ]; then
		echo "{\"error\":\"Bad arguments\"}"
		return
	fi
	path=( "\"$a\"" )
	next_hop=""
	while [ "$next_hop" != "$b" ]; do
		next_hop=$(ssh root@$a "source /root/node/collect_feature_data.sh; get_hwmp_routes_json | jq .$b.next_hop" | sed 's/\"//g')
		if [ -z "$next_hop" ] || [ "$next_hop" == "null" ]; then
			echo "{\"error\":\"Routes command returned $next_hop\"}"
			return
		fi
		path+=( \"$next_hop\" )
		a="$next_hop"
	done
	raw=$(echo \["${path[@]}"\] | sed 's/ /,/g')
	jq -n --argjson route "$raw" --arg from "$1" --arg to "$2" '{route:$route, from: $from, to: $to}'
}

function meshtestbed_get_route()
{
	if [ "$HWMP" == true ]; then
		meshtestbed_hwmp_get_route $1 $2
	else
		meshtestbed_batman_get_route $1 $2
	fi
}

function start_iperf3_server()
{
	# In case iperf was active from before
	# $DEBUG ssh $UNAME@$RECEIVER "killall iperf3" > /dev/null 2>&1 &
	# $DEBUG ssh $UNAME@$TRANSMITTER "killall iperf3" > /dev/null 2>&1 &
	outfilename="$1"
	if [ -z "$outfilename" ]; then
		outfilename=$RESULTS_DIR/"iperf_server.json"
	fi

	if [ "$ALL_TO_ONE" == true ]; then
		# If it's all to one, run iperf3 server with port 999$id where $id is the intended transmitter's id (i.e. 0 for spitz0)
		for i in ${targets[@]}; do
			target=$(echo $i | awk '{print $2}')
			[ "$target" == "$RECEIVER" ] && continue
			id=$(echo $target | sed 's/spitz//g')
			port="999"$id
			$DEBUG ssh $UNAME@$RECEIVER "iperf3 -D -s -B $RECEIVER_IP -p $port" &
		done
	else
		# If it's a single tx single rx situation, just run the iperf3 daemon on the rx
		$DEBUG ssh $UNAME@$RECEIVER "iperf3 -s $RECEIVER_IP $JSON --verbose -1" > $outfilename &
	fi
	# wait $(jobs -p)
}

function start_iperf3_client()
{
	outfilename="$1"
	if [ -z "$outfilename" ]; then
		outfilename=$RESULTS_DIR/"iperf_client.json"
	fi
	if [ "$PAYLOAD_MODE" == true ]; then
		echo "[*] iperf Payload mode"
		$DEBUG ssh $UNAME@$TRANSMITTER "iperf3 -c $RECEIVER_IP -n $PAYLOAD_SIZE -u -b $BITRATE $JSON --verbose" | tee $outfilename
	else
		echo "[*] iperf Timed mode"
		$DEBUG ssh $UNAME@$TRANSMITTER "iperf3 -c $RECEIVER_IP -t $RUN_TIME -u $JSON -b $BITRATE --verbose" | tee $outfilename
	fi
	wait $(jobs -p)
}

function start_ping()
{
	outfilename="$1"
	if [ -z "$outfilename" ] ; then 
		outfilename=$RESULTS_DIR/"ping.out"
	fi
	$DEBUG ssh $UNAME@$TRANSMITTER "ping -I br-mesh -w $RUN_TIME -p 31 -i 1 $RECEIVER_IP | while read pong; do echo \$EPOCHSECONDS: \$pong; done" | tee $outfilename &
	wait $(jobs -p)
}

# "blank" meaning just sit and not do anything. 
# for batman mgmt data collection purposes
function start_blank()
{
	sleep $RUN_TIME
}

function kill_ping()
{
	$DEBUG ssh $UNAME@$TRANSMITTER "killall ping"
}

function meshtestbed_kill_mesh_radio()
{
	echo "[*] Killing $1"
	if [ -z "$1" ]; then
		echo "[!] No node given!"	
	else
		# ssh root@"$1" "uci set wireless.radio0.disabled='1'; uci commit wireless; wifi"
		# ssh root@"$1" "ifconfig phy0-mesh0 down"
		ssh root@"$1" "wifi down"
	fi
}

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

function node_killer_process()
{
	# set -x
	startTimestamp="$1"
	intermediaryNodeStreak=0
	intermediaryNode=""
	echo "[*] Node killer will run at $startTimestamp"
	while [ "$startTimestamp" -gt "$EPOCHSECONDS" ]; do
		: # wait until the start timestamp arrives
	done
	echo "[*] Beginnging node killer process"

	# 1) Pick node to kill
	while [ "$intermediaryNodeStreak" -lt 3 ]; do

		# Get current route
		A="$TRANSMITTER"
		B="$RECEIVER"
		if [ $TRANSMITTER == "nuc0" ]; then
			A="spitz0"
		fi
		routeAtoB="$(meshtestbed_get_route $A $B)"
		echo "$routeAtoB"
		sleep 0.5

		# Make sure there's a hop
		if [ $(echo "$routeAtoB" | jq '.route' | jq length) -lt 3 ]; then
			echo "[!] No hops in between!"
			intermediaryNodeStreak=0
			continue
		fi

		# Count streak
		intermediaryAtoB=$(echo "$routeAtoB" | jq '.route[1]' | sed 's/"//g')
		if [ "$intermediaryNode" == "$intermediaryAtoB" ] ; then
			intermediaryNodeStreak=$(($intermediaryNodeStreak + 1))
		else
			intermediaryNodeStreak=0
			intermediaryNode="$intermediaryAtoB"
		fi

		echo "[*] Intermediary node from $A to $B" : "$intermediaryNode", Streak: "$intermediaryNodeStreak"

	done

	killTimestamp=$(echo "$EPOCHREALTIME" | sed 's/,/./g')
	echo "[*] Killing $intermediaryNode at timestamp $killTimestamp"

	# 2) Kill the node
	meshtestbed_kill_mesh_radio "$intermediaryNode"
	sleep 0.5

	if [ "$PING" == true ]; then
		echo "$intermediaryNode killed at $killTimestamp" >> $PING_FILENAME
	fi

	# 3) Poll while route is reestablished
	routePoll="error" 
	while [[ "$routePoll" =~ "error" ]]; do
		routePoll="$(meshtestbed_get_route $TRANSMITTER $RECEIVER $intermediaryNode)"
		echo $EPOCHREALTIME $routePoll
		sleep 0.5
	done

	# 4) Route reestablished. Log it and revive our dead node
	reconnectTimestamp=$(echo "$EPOCHREALTIME" | sed 's/,/./g')
	echo "[*] Connection reestablished at $reconnectTimestamp. Reviving..."
	# meshtestbed_revive_mesh_radio "$intermediaryNode"

	if [ "$PCAP" == true ]; then # If pcap was enabled, killing the radio will also kill the pcap. restart it
		$DEBUG ssh $UNAME@$intermediaryNode "tcpdump -i phy0-mon0 $filterStr -w /root/experiment_contd.pcap" &
	fi

	# 5) Save stats
	reconnectionTime=$(bc <<< "$reconnectTimestamp - $killTimestamp")
	jq -n --argjson reconnection_time "$reconnectionTime" \
		--argjson route_a_to_b "$routeAtoB" \
		--arg killed_node "$intermediaryNode" \
		--argjson kill_timestamp "$killTimestamp" \
		--argjson reconnection_timestamp "$reconnectTimestamp" \
		'{route_a_to_b:$route_a_to_b, killed_node:$killed_node, kill_timestamp:$kill_timestamp, reconnection_timestamp:$reconnection_timestamp, reconnection_time:$reconnection_time}' | tee $RESULTS_DIR/node_killer.json
}

function sigint_handler()
{
	trap - SIGINT
	echo "[*] Received sigint. killing iperf pid or ping pid"
	kill $iperf_pid
	kill $ping_pid
	exit 1
}

trap sigint_handler SIGINT

# NODE KILLER TEST
# echo "Testing node killer"
# t0="$EPOCHSECONDS"
# t1=$(($t0 + 5))
# echo "NOW $t0"
# node_killer_process $t1 &
# wait $(jobs -p)
# exit
# #


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
		"--poll_period") # Seconds to wait inbetween trials
			shift
			POLL_PERIOD="$1"
			shift
			;;
		"--run_time") # Number of trials to run
			shift
			RUN_TIME="$1"
			shift
			;;
		"--name") # Prefix to the results directory name
			shift
			EXPERIMENT_NAME="$1"
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
		"--mongo") # Enable saving to mongo database
			shift
			MONGO=true
			;;
		"--no_iperf") # Dont run iperf
			shift
			IPERF=false
			;;
		"--ping")
			shift
			PING=true
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
		"--hwmp") # Use hwmp tooling
			echo "[*] Using HWMP"
			HWMP=true
			shift
			;;
		"--batman")
			echo "[*] Using BATMAN"
			BATMAN=true
			shift
			;;
		"--node_kill_at") # Time to start the node killing procedure
			shift
			NODE_KILL_AT="$1"
			shift
			;;
		"--pcap") # Enable packet capturing (~10 seconds seems to get you a 1.5MB file so proceed with caution)
			PCAP=true
			shift
			;;
		"--mesh_path_refresh_time")
			shift
			mesh_path_refresh_time="$1"
			shift
			;;
		"--mesh_hwmp_preq_min_interval")
			shift
			mesh_hwmp_preq_min_interval="$1"
			shift
			;;
		"--mesh_hwmp_max_preq_retries")
			shift
			mesh_hwmp_max_preq_retries="$1"
			shift
			;;
		"--mesh_hwmp_active_path_timeout")
			shift
			mesh_hwmp_active_path_timeout="$1"
			shift
			;;
		"--payload_mode")
			PAYLOAD_MODE=true
			shift
			;;
		"--blank")
			IPERF=false
			PING=false
			BLANK=true
			shift
			;;
		"--exclude_node")
			shift
			excludeStr="$excludeStr $1"
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

# Iperf json filename
IPERF_CLIENT_RESULTS_FILENAME="$RESULTS_DIR"/iperf_client_"$TRANSMITTER"_"$RECEIVER".json
IPERF_SERVER_RESULTS_FILENAME="$RESULTS_DIR"/iperf_server_"$TRANSMITTER"_"$RECEIVER".json
PING_FILENAME="$RESULTS_DIR"/ping_"$TRANSMITTER"_"$RECEIVER".out

# Create subdir for consolidated json files
mkdir -p "$RESULTS_DIR"/consolidated

# Note down experiment settings in a file
config_data=$(jq -n \
	--arg run_time "$RUN_TIME" \
	--arg poll_period "$POLL_PERIOD" \
	--arg txpower "$TXPOWER" \
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
	--arg hwmp "$HWMP" \
	--arg batman "$BATMAN" \
	--arg cmdline "$CMDLINE" \
	--arg node_kill_at "$NODE_KILL_AT" \
	--argjson mesh_path_refresh_time "$mesh_path_refresh_time" \
	--argjson mesh_hwmp_preq_min_interval "$mesh_hwmp_preq_min_interval" \
	--argjson mesh_hwmp_max_preq_retries "$mesh_hwmp_max_preq_retries" \
	--argjson mesh_hwmp_active_path_timeout "$mesh_hwmp_active_path_timeout" \
	'{run_time: $run_time, poll_period: $poll_period, txpower: $txpower, bitrate: $bitrate, bitrate_sweep: $bitrate_sweep, bitrate_sweep_num_trials: $bitrate_sweep_num_trials, bitrate_sweep_increment: $bitrate_sweep_increment, bitrate_sweep_increment_until: $bitrate_sweep_increment_until, ogm_interval: $ogm_interval, ogm_interval_sweep: $ogm_interval_sweep, ogm_interval_sweep_increment: $ogm_interval_sweep_increment, ogm_interval_sweep_num_trials: $ogm_interval_sweep_num_trials, tx: $tx, rx: $rx, a2o: $a2o, randtx: $randtx, randtx_numtrials: $randtx_numtrials, batman:$batman, hwmp: $hwmp, node_kill_at: $node_kill_at, mesh_path_refresh_time: $mesh_path_refresh_time, mesh_hwmp_preq_min_interval: $mesh_hwmp_preq_min_interval, mesh_hwmp_max_preq_retries: $mesh_hwmp_max_preq_retries, mesh_hwmp_active_path_timeout: $mesh_hwmp_active_path_timeout, cmdline: $cmdline}')
echo "$config_data" > "$RESULTS_DIR"/.config

if [ "$MONGO" == true ]; then 
	echo "[*] MongoDB database: $MONGO_DB"
	$DEBUG save_to_mongo "$RESULTS_DIR/.config" "config" 
fi

echo "[*] Experiment configuration:"
cat "$RESULTS_DIR"/.config 

##################################################################################

# set -x

revive_all

# First, set tx powers of our targets to our initial txpower
set_txpowers $TXPOWER

# Then, if we have any specific router txpowers, set them too
echo "ROUTER TXPOWER LEN ${#ROUTER_TXPOWER[@]}"
for i in $(seq 0 $((${#ROUTER_TXPOWER[@]}-1))) ; do
	router=$(echo ${ROUTER_TXPOWER[$i]} | awk '{print $1}')
	txpower=$(echo ${ROUTER_TXPOWER[$i]} | awk '{print $2}')
	set_router_txpower "$router" "$txpower" 
done

# Start ##########################################################################

# 1) Get before timestamp. no need to get stats since we're resetting wifi just before
before_timestamp=$(echo $EPOCHREALTIME | sed 's/,/./g')

# Get BATMAN/HWMP statistics
if [ "$BATMAN" == true ]; then
	echo "[*] Getting BATMAN statistics"
	before_mgmt_tx=0
	before_mgmt_tx_bytes=0
	before_tx=0
	before_tx_bytes=0
	before_tx_dropped=0
	before_forward_pkts=0
	before_forward_bytes=0
	before_pkts=0
	before_bytes=0
	for t in ${targets[@]}; do
		target=$(echo $t | awk '{print $2}')
		batman_stats=$(ssh $UNAME@$target "source node/collect_feature_data.sh; get_batman_statistics_json")
		before_mgmt_tx=$(($before_mgmt_tx + $(echo "$batman_stats" | jq '.mgmt_tx')))
		before_mgmt_tx_bytes=$(($before_mgmt_tx_bytes + $(echo "$batman_stats" | jq '.mgmt_tx_bytes')))
		before_tx=$(($before_tx + $(echo "$batman_stats" | jq ".tx")))
		before_tx_bytes=$(($before_tx_bytes + $(echo "$batman_stats" | jq ".tx_bytes")))
		before_tx_dropped=$(($before_tx_dropped + $(echo "$batman_stats" | jq ".tx_dropped")))
		before_forward_pkts=$(($before_forward_pkts + $(echo "$batman_stats" | jq ".forward_pkts")))
		before_forward_bytes=$(($before_forward_bytes + $(echo "$batman_stats" | jq ".forward_bytes")))
		before_pkts=$(($before_pkts + $before_tx + $before_mgmt_tx + $before_forward_pkts))
		before_bytes=$(($before_bytes + $before_tx_bytes + $before_mgmt_tx_bytes + $before_forward_bytes))
		echo "$batman_stats" > $RESULTS_DIR/"$target"_before_batman_stats.json
	done

elif [ "$HWMP" == true ]; then
	echo "[*] Getting HWMP statistics"
fi

# Set our mesh params
if [ "$HWMP" == true ]; then
	echo "[*] HWMP"
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')	
		$DEBUG ssh $UNAME@$target "iw dev phy0-mesh0 set mesh_param mesh_path_refresh_time $mesh_path_refresh_time mesh_hwmp_preq_min_interval $mesh_hwmp_preq_min_interval mesh_hwmp_max_preq_retries $mesh_hwmp_max_preq_retries mesh_hwmp_active_path_timeout $mesh_hwmp_active_path_timeout" &
	done
	wait $(jobs -p)
elif [ "$BATMAN" == true ]; then
	echo "[*] BATMAN"
	set_ogm_interval $OGM_INTERVAL
fi

echo "[*] Mesh params set. Waiting 3 seconds for them to set in"
sleep 3

# If desired start capturing packets
if [ "$PCAP" == true ]; then
	for i in $(seq 0 $((${#targets[@]}-1))) ; do
		macPrefix+="ether src $macPrefix:0$i "
	done
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		$DEBUG ssh $UNAME@$target "tcpdump -i phy0-mon0 $filterStr -w /root/experiment.pcap" &
		disown $(jobs -p)
	done
fi

# Run iperf3 daemon or ping on the target machine ###################################
if [ "$IPERF" == true ] ; then
	kill_iperf3
	start_iperf3_server $IPERF_SERVER_RESULTS_FILENAME
	disown $(jobs -p)

	# Run the experiments #############################################################
	# I want one thread to run the iperf
	echo "[*] Starting iperf3 run from $TRANSMITTER to $RECEIVER for $RUN_TIME seconds"
	start_iperf3_client $IPERF_CLIENT_RESULTS_FILENAME &
	iperf_timestamp="$EPOCHREALTIME"
	iperf_pid=$(jobs -p)
	disown $iperf_pid
	echo "[*] iperf pid $iperf_pid"

elif [ "$PING" == true ]; then
	start_ping $PING_FILENAME &
	ping_timestamp="$EPOCHREALTIME"
	ping_pid=$(jobs -p)
	disown $ping_pid
	echo "[*] ping pid $ping_pid"

elif [ "$BLANK" == true ]; then
	start_blank &
	blank_timestamp="$EPOCHREALTIME"
	blank_pid=$(jobs -p)
	disown $blank_pid
	echo "[*] blank pid $blank_pid"
fi

if [ "$NODE_KILL_AT" -gt 0 ]; then
	t0="$EPOCHSECONDS"
	t1=$(($t0 + "$NODE_KILL_AT"))
	node_killer_process $t1 &
	node_killer_pid=$(jobs -p)
	disown $node_killer_pid 
fi

# In parallel, we poll for passive data
t=0 # Trial count
while true; do
	# Check if Iperf process is done
	if [ "$IPERF" == true ] && [ ! -d "/proc/$iperf_pid/" ]; then 
		echo "[*] Iperf run finished"
		break
	elif [ "$PING" == true ] && [ ! -d "/proc/$ping_pid/" ]; then
		echo "[*] Ping run finished"
		break
	elif [ "$BLANK" == true ] && [ ! -d "/proc/$blank_pid/" ]; then
		echo "[*] Blank run finished"
		break
	# elif [ ! -d "/proc/$node_killer_pid" ]; then
		# echo "[*] Node killer finished"
		# break
	fi
	
	# # For every target poll RSSI and batman routes ##################################
	# if [ "$POLL_PERIOD" -gt 0 ]; then 
	# 	tt=$(printf "%06g" $t) # Trial number with padding 0s
	# 	local_timestamp=$(echo $EPOCHREALTIME | sed 's/,/./g')
	# 	for i in ${targets[@]}; do
	# 		target=$(echo $i | awk '{print $2}')
	# 		ip=$(echo $i | awk '{print $1}')
	# 		if [ "$HWMP" ]; then
	# 			$DEBUG ssh $UNAME@$target "source /root/node/collect_feature_data.sh; get_hwmp_pktloss_rssi_noise_deployment_data $local_timestamp $t" > "$RESULTS_DIR"/"$target"/stationdump_"$tt".json &
	# 			$DEBUG ssh $UNAME@$target "source /root/node/collect_feature_data.sh; get_hwmp_routes_json" > "$RESULTS_DIR"/"$target"/routes_"$tt".json &
	# 		else
	# 			$DEBUG ssh $UNAME@$target "source /root/node/collect_feature_data.sh; get_pktloss_rssi_noise_deployment_data $local_timestamp $t" > "$RESULTS_DIR"/"$target"/stationdump_"$tt".json &
	# 			$DEBUG ssh $UNAME@$target "source /root/node/collect_feature_data.sh; get_batman_routes_json" > "$RESULTS_DIR"/"$target"/routes_"$tt".json &
	# 		fi
	# 	done
	# 	wait $(jobs -p)
	# 	
	# 	t=$(($t+1))
	# 	sleep $POLL_PERIOD
	# fi

done

after_timestamp=$(echo $EPOCHREALTIME | sed 's/,/./g')
experiment_time=$(bc <<< "$after_timestamp - $before_timestamp")

# Get after BATMAN/HWMP statistics
if [ "$BATMAN" == true ]; then
	echo "[*] Getting BATMAN statistics"
	for t in ${targets[@]}; do
		target=$(echo $t | awk '{print $2}')
		batman_stats=$(ssh $UNAME@$target "source node/collect_feature_data.sh; get_batman_statistics_json")
		echo "$batman_stats" > $RESULTS_DIR/"$target"_after_batman_stats.json
	done

	json_consolidator $RESULTS_DIR

elif [ "$HWMP" == true ]; then
	echo "[*] Getting HWMP statistics"
fi

# If pcap was on, retrieve pcap files and remove them from the router 
if [ "$PCAP" == true ]; then

	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		$DEBUG ssh $UNAME@$target "killall tcpdump"
	done

	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		$DEBUG scp $UNAME@$target:/root/experiment.pcap $RESULTS_DIR/"$target".pcap
		$DEBUG scp $UNAME@$target:/root/experiment_contd.pcap $RESULTS_DIR/"$target"_contd.pcap
		if [ $? == 0 ]; then # this means there was a fragmented pcap file. merge them
			mergecap $RESULTS_DIR/"$target".pcap $RESULTS_DIR/"$target"_contd.pcap -w $RESULTS_DIR/"$target"_tmp.pcap
			mv $RESULTS_DIR/"$target"_tmp.pcap $RESULTS_DIR/"$target".pcap
			rm $RESULTS_DIR/"$target"_contd.pcap
		fi
	done
	
	for i in ${targets[@]}; do
		target=$(echo $i | awk '{print $2}')
		$DEBUG ssh $UNAME@$target "rm /root/experiment*.pcap; wifi" # just as a precaution, reset the wifi iface
	done

fi

kill_ping
kill_iperf3
echo "[*] Done"

