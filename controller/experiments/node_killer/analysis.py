#!/usr/bin/env python3
import sys, os, json, traceback, pdb
import argparse
import matplotlib.pyplot as plt
from pprint import pprint

# Usage: ./analysis.py 

runs = {} # Organized as txpower:ogm_interval:run data
def main(savefigs=False):
    # First get our json files into memory 
    for filename in sys.argv[1:]:
        f = open(filename, "r")
        jsonContents = ""
        try:
            jsonContents = json.load(f)
        except Exception as e:
            print(f"[!] Error while reading json file {filename}")
            traceback.print_exc()
        f.close()
        
        # Lets organize these by txpower:ogm_interval:run data
        txpower = jsonContents["txpower"]
        ogm_interval = jsonContents["ogm_interval"]

        if txpower not in runs:
            runs[txpower] = {}
        if ogm_interval not in runs[txpower]:
            runs[txpower][ogm_interval] = []
        jsonContents["mgmt_tx_per_second"] = jsonContents["mgmt_tx"] / jsonContents["experiment_time"]
        jsonContents["mgmt_tx_bytes_per_second"] = jsonContents["mgmt_tx_bytes"] / jsonContents["experiment_time"]

        if (jsonContents["reconnection_time"] > 150 and jsonContents["txpower"] == 2000):
            print("BIG BOI", filename, jsonContents["reconnection_time"])
            continue

        runs[txpower][ogm_interval].append(jsonContents)

    # At this point we have our json files in the $runs dictionary
    # We can average them and plot them 
    plt.rcParams["figure.figsize"] = (15, 10) # Figure size
    for txpower in sorted(runs):
        fig, ax = plt.subplots(nrows=2, ncols=1)
        fig.suptitle(f"{txpower/100} dBm TxPower OGM Interval Sweep")

        # Set up axes
        for axis in ax:
            axis.grid(True, which="both")

        # Set up data to be displayed
        avg_reconnection_time_arr = []
        avg_mgmt_tx_bytes_per_second_arr = []
        ogm_interval_arr = []
        for ogm_interval in sorted(runs[txpower]):
            runsArr = runs[txpower][ogm_interval]

            avg_mgmt_tx = sum([i["mgmt_tx"] for i in runsArr]) / len(runsArr)
            avg_mgmt_tx_bytes = sum([i["mgmt_tx_bytes"] for i in runsArr]) / len(runsArr)
            avg_mgmt_tx_per_second = sum([i["mgmt_tx_per_second"] for i in runsArr]) / len(runsArr)
            avg_mgmt_tx_bytes_per_second = sum([i["mgmt_tx_bytes_per_second"] for i in runsArr]) / len(runsArr)
            avg_reconnection_time = sum([i["reconnection_time"] for i in runsArr]) / len(runsArr)

            avg_reconnection_time_arr.append(avg_reconnection_time)
            avg_mgmt_tx_bytes_per_second_arr.append(avg_mgmt_tx_bytes_per_second)
            ogm_interval_arr.append(ogm_interval/1000)
    
        # Actually do the plotting
        ax[0].scatter(ogm_interval_arr, avg_reconnection_time_arr, c="tab:blue")
        ax[0].plot(ogm_interval_arr, avg_reconnection_time_arr, c="tab:blue")
        ax[0].set_ylim(0, 100)
        ax[0].set_xlabel("OGM Interval (Seconds)")
        ax[0].set_ylabel("Reconnection Time (Seconds)")

        ax[1].scatter(ogm_interval_arr, avg_mgmt_tx_bytes_per_second_arr, c="tab:purple")
        ax[1].plot(ogm_interval_arr, avg_mgmt_tx_bytes_per_second_arr, c="tab:purple")
        ax[1].set_xlabel("OGM Interval (Seconds)")
        ax[1].set_ylabel("MGMT TX Bytes Per Second")
        
        ax[1].set_yscale('log')
        ax[1].set_ylim(100, 15000)

        if (savefigs):
            plt.savefig(f"./connectivity_{txpower}_dbm.png")
        else:
            plt.show()

if __name__ == "__main__":
    # font = {'family' : 'normal' , 'weight' : 'bold' , 'size' : 19} # FOR THE ERICSSON REPORT
    # plt.rc('font', **font)
    savefigs = "--savefigs" in sys.argv
    if (savefigs):
        sys.argv.pop(sys.argv.index("--savefigs"))
    main(savefigs)
