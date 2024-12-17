#!/usr/bin/env bash

if [[ -z "$SPITZ_CONTROLLER_DIR" ]]; then # if the controller dir env variable is not set
	SPITZ_CONTROLLER_DIR="/home/jon/KODMOD/spitz_box/controller/" 
fi	

# Disable ansible fact gathering
export ANSIBLE_GATHERING=explicit

function meshtestbed_tmux()
{
	tmux new-session -d

	tmux send-keys "ssh root@spitz0" C-m
	tmux send-keys "clear" C-m
	tmux split-window -v

	tmux send-keys "ssh root@spitz1" C-m
	tmux send-keys "clear" C-m
	tmux split-window -v

	tmux send-keys "ssh root@spitz2" C-m
	tmux send-keys "clear" C-m

	tmux select-layout main-vertical 
	tmux -2 attach-session -d
}

function meshtestbed_sync_testbed()
{
	ansible-playbook -i $SPITZ_CONTROLLER_DIR/inventory.yaml $SPITZ_CONTROLLER_DIR/sync_testbed_playbook.yaml
}

function meshtestbed_cmd()
{
	ansible-playbook -i $SPITZ_CONTROLLER_DIR/inventory.yaml $SPITZ_CONTROLLER_DIR/command_playbook.yaml --extra-vars "{\"cmd\":\"$@\"}" 
}

function meshtestbed_retrieve_results()
{
	ansible-playbook -i $SPITZ_CONTROLLER_DIR/inventory.yaml $SPITZ_CONTROLLER_DIR/retrieve_results_playbook.yaml
}

function meshtestbed_run_time_drift_experiment()
{
	meshtestbed_cmd "bash /root/node/experiments/time_drift/run_time_drift.sh"
}

function meshtestbed_reboot()
{
	ansible-playbook -i $SPITZ_CONTROLLER_DIR/inventory.yaml $SPITZ_CONTROLLER_DIR/reboot_playbook.yaml
}

function meshtestbed_run_and_retrieve_backup()
{
	meshtestbed_cmd "bash /root/node/generate_conf_backup.sh"
	sleep 2
	ansible-playbook -i $SPITZ_CONTROLLER_DIR/inventory.yaml $SPITZ_CONTROLLER_DIR/retrieve_backups_playbook.yaml
}

function meshtestbed_txpower()
{
	txpower="$1"
	meshtestbed_cmd "iw dev phy0-mesh0 set txpower fixed $txpower"
}

function meshtestbed_orig_interval()
{
	interval="$1"
	meshtestbed_cmd "batctl it $interval"
}

function meshtestbed_set_5ghz()
{
	# If nothing is passed this will disable the 5ghz radio
	if [ -z "$1" ]; then
		# Nothing is pased
		echo "Disabling 5GHz radio"
		meshtestbed_cmd "uci set wireless.radio1.disabled='1'; uci commit wireless; wifi"
	else
		# Something is passed
		echo "Enabling 5GHz radio"
		meshtestbed_cmd "uci set wireless.radio1.disabled='0'; uci commit wireless; wifi"
	fi
}

function meshtestbed_kill_mesh_radio()
{
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
}

# $1: source $2: destination hostnames
# returns path from $1 to $2
# BATMAN
function meshtestbed_get_route()
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
		next_hop=$(ssh root@$a "source node/collect_feature_data.sh; get_batman_routes_json | jq .$b.next_hop" | sed 's/\"//g')
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
		next_hop=$(ssh root@$a "source node/collect_feature_data.sh; get_hwmp_routes_json | jq .$b.next_hop" | sed 's/\"//g')
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
