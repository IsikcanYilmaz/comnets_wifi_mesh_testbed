#!/usr/bin/env python3

import sys, os, json, argparse, pdb, pprint, traceback
import matplotlib.pyplot as plt
import numpy as np

# Usage: ./continuous_iperf_analyze.py <results dirname>

# Fuck it. we use globals
seconds = []

def parsePcapFile(filepath):
    print("PCAP FILE:", filepath)

def parseIperfFile(filepath, savefig=False, figtitle="node killer"):
    print("IPERF FILE:", filepath)
    # jsonContents = json.loads(filepath)
    try:
        f = open(filepath, "r")
        jsonContents = json.load(f)
        f.close()
    except Exception as e:
        print(f"Error reading json file {filepath}")
        traceback.print_exc()
        return

    # print(f"Total lost percent: {jsonContents['end']['sum_received']['lost_percent']}")
    
    # Expectation is that this json file has a field named "intervals" which is a list. every element of this list
    # represents one second of the experiment
    # fig, ax = plt.subplots(2,1)
    fig, ax = plt.subplots()

    # Loss percent plot
    # ax[0].set_ylim(-1, 100)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Bitrate (Received)")
    # ax[0].scatter([i for i in range(0, len(jsonContents["intervals"]))], [interval["sum"]["lost_percent"] for interval in jsonContents["intervals"]], s=10)
    ax.plot([i for i in range(0, len(jsonContents["intervals"]))], [interval["sum"]["bits_per_second"] for interval in jsonContents["intervals"]])

    # Jitter plot
    # ax[1].set_xlabel("Time (s)")
    # ax[1].set_ylabel("Jitter (Ms)")
    # ax[1].scatter([i for i in range(0, len(jsonContents["intervals"]))], [interval["sum"]["jitter_ms"] for interval in jsonContents["intervals"]], s=10)
    #
    plt.suptitle(figtitle)
    # plt.show()

    plt.savefig(f"{figtitle.replace(' ', '_')}.png")

def main(dirname):
    print("RESULTS DIR:", dirname)
    origDir = os.curdir
    os.chdir(dirname)

    f = open(".config", "r")
    config = json.load(f)
    f.close()
    
    figname = f'OGM Interval {config["ogm_interval"]} Tx Power {config["txpower"]} dBm'

    for f in os.listdir("."):
        if "iperf_server" in f:
            parseIperfFile(f, figtitle=figname, savefig=True)
        if "pcap" in f:
            parsePcapFile(f)


    os.chdir(origDir)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dirname")
    args = parser.parse_args()
    main(args.dirname)
