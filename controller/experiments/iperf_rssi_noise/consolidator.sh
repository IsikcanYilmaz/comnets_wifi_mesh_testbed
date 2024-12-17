#!/usr/bin/env bash

# Consolidator. Consolidates and pre-preprocesses output files from pktdrop_rssi_deployment.sh
# ! Consolidates _one_ trial (iperfs, station dumps, routes). Doesnt consolidate anymore !
# Tbh prolly shouldnt be used outside of pktdrop_rssi_deployment.sh
# This file basically exists to lift some weight off of the main experiment script
# ./consolidator.sh <experiment results dir> <trial number> <optional timestamp>
# Expects a directory that has the spitzN subdirectories and iperf_x_y subdirectories 
#
# # TODO consolidated_filename maybe dont set a filename here, just print to stdout. let the caller
# do whatever they want?

IFS=$'\n'
targets=( $(cat /etc/hosts | grep spitz | grep -v \# | grep -v testbed | grep -v localhost) )

results_dir=$1
trial_num=$2
padded_trial_num=$(printf "%06g" $trial_num) # Trial number with padding 0s
if [ -z "$3" ]; then 
	local_timestamp=$(echo $EPOCHREALTIME | sed 's/,/./g')
else
	local_timestamp="$3"
fi

cd $results_dir
mkdir -p consolidated 
consolidated_filename="./consolidated/trial_"$padded_trial_num".json"

# TODO break out of this if an error happens
function recurse_route()
{
	# recurse_route x y trial_padded "route_so_far"
	# where x is the origin y is the destination router
	# trial_padded is %06 padded trial number
	# route so far is empty initially
	# Assumes we're in the results dir
	x="$1"
	y="$2"
	trial="$3"
	route_so_far="$4"

	# If we've reached the destination, return
	if [ "$x" == "$y" ]; then
		route_so_far="$route_so_far,$y"
		echo $route_so_far
		return
	fi
	
	# Append to the end result string
	if [ -z $route_so_far ] ; then
		route_so_far="$x"
	else
		route_so_far=$route_so_far,"$x"
	fi

	# Get the next hop of x, set that as the next x and recurse 
	routefile=$x/routes_$trial".json"
	next_hop=$(cat $routefile | jq ".$y[\"next_hop\"]" | sed 's/\"//g')

	if [ "$?" != 0 ]; then
		echo "error"
		return
	else
		recurse_route "$next_hop" "$y" "$trial" "$route_so_far" 
	fi
}

# Consolidate iperfs stationdumps and routes into the following:
# { "trial":x, "timestamp":x, "stationdump":{ "spitzx": {}, ... }, 
# "routes" : { "spitzx": {}, ... } , "iperf" : [ {}, {}, {} ] }

echo "{ \"trial\" : $trial_num , \"timestamp\" : $local_timestamp , " > $consolidated_filename
echo " \"station_dump\" : { " >> $consolidated_filename 
for i in $(seq 0 $((${#targets[@]}-1))); do
	target=$(echo ${targets[$i]} | awk '{print $2}')
	# echo $i $target
	echo "\"$target\" : " >> $consolidated_filename
	stationdump_data=$(cat "$target"/"stationdump_"$padded_trial_num".json")
	if [ -z "$stationdump_data" ]; then
		echo "{}" >> $consolidated_filename;
	else 
		echo "$stationdump_data" >> $consolidated_filename; 
	fi
	[ $i -lt $((${#targets[@]}-1)) ] && echo "," >> $consolidated_filename
done
echo "}, " >> $consolidated_filename

echo "\"routes\" : { " >> $consolidated_filename # TODO maybe make this entire routes?
for i in $(seq 0 $((${#targets[@]}-1))); do
	target=$(echo ${targets[$i]} | awk '{print $2}')
	echo "\"$target\" : " >> $consolidated_filename
	routes_data=$(cat "$target"/"routes_"$padded_trial_num".json")
	if [ -z "$routes_data" ]; then
		echo "{}" >> $consolidated_filename
	else
		echo "$routes_data" >> $consolidated_filename
	fi
	[ $i -lt $((${#targets[@]}-1)) ] && echo "," >> $consolidated_filename
done
echo "}" >> $consolidated_filename

echo ", \"iperf\" : [" >> $consolidated_filename
# Handle iperfs and routes
iperfblock=$(for iperf_dir in $(ls | grep iperf); do
	# Handle iperf file
	transmitter=$(echo $iperf_dir | awk -F_ '{print $2}')
	receiver=$(echo $iperf_dir | awk -F_ '{print $3}')
	iperf_file="$iperf_dir"/iperf_$padded_trial_num".json"
	echo "{ \"transmitter\" : \"$transmitter\" , \"receiver\" : \"$receiver\" , \"results\" :" 
	iperf_contents=$(cat $iperf_file)
	[ -z "$iperf_contents" ] && iperf_contents="{\"error\":\"file empty\"}"
	echo "$iperf_contents"

	# Handle route
	echo ", \"route\" : [" 
	firstmeshnode=$transmitter
	if [[ "spitz" != *"$transmitter"* ]] ; then # Our transmitter is not a router. populate $firstmeshnode with the name of  the router that our tx machine is connected to
		firstmeshnode="spitz"$(echo $transmitter | sed "s/${transmitter::-1}//g")
	fi
	echo \"$(recurse_route $firstmeshnode $receiver $padded_trial_num | sed 's/,/\",\"/g')\"
	echo "]},"
done)
echo ${iperfblock::-1} >> $consolidated_filename # the ::-1 removes the trailing comma
echo "]" >> $consolidated_filename
echo "}" >> $consolidated_filename
cat $consolidated_filename | jq > $consolidated_filename"_tmp"
mv $consolidated_filename"_tmp" "$consolidated_filename"
echo "Consolidated $results_dir $trial_num - $consolidated_filename"
