#!/usr/bin/env bash

# sender with high and low tx, receiver with high and low tx.

NUM_TRIALS=10000

# # 1) sender high, receiver low
# ./pktloss_rssi_noise_deployment.sh --name "aswin_sender_high_receiver_low" --txpower 1500 --router_txpower "spitz0 2000" --router_txpower "spitz3 1000" --sleep 0 --nuc_tx --no_mongo --bitrate 20M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000
#
# # 2) sender low, receiver high
# ./pktloss_rssi_noise_deployment.sh --name "aswin_sender_low_receiver_high" --txpower 1500 --router_txpower "spitz0 1000" --router_txpower "spitz3 2000" --sleep 0 --nuc_tx --no_mongo --bitrate 20M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000
#
# # 3) sender low, receiver low
# ./pktloss_rssi_noise_deployment.sh --name "aswin_sender_low_receiver_low" --txpower 1500 --router_txpower "spitz0 1000" --router_txpower "spitz3 1000" --sleep 0 --nuc_tx --no_mongo --bitrate 20M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000
#
# # 4) sender high, receiver high
# ./pktloss_rssi_noise_deployment.sh --name "aswin_sender_high_receiver_high" --txpower 1500 --router_txpower "spitz0 2000" --router_txpower "spitz3 2000" --sleep 0 --nuc_tx --no_mongo --bitrate 20M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000

# Bitrate ones
./pktloss_rssi_noise_deployment.sh --name "aswin_bitrate_high" --txpower 2000 --random_txpower --random_txpower_num_trials 10 --sleep 0 --nuc_tx --no_mongo --bitrate 20M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000

./pktloss_rssi_noise_deployment.sh --name "aswin_bitrate_low" --txpower 2000 --random_txpower --random_txpower_num_trials 10 --sleep 0 --nuc_tx --no_mongo --bitrate 1M --payload_size 1M --num_trials $NUM_TRIALS --ogm_interval 1000
