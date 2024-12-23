#!/usr/bin/env python3

usage="""
./analyze.py <dir name> 
Where <dir name> is the directory generated by rssi_noise_deployment.sh
"""

# import pdb
import sys, os, subprocess, json, traceback
import pprint
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

routers = {
    "spitz0":{
        "mac":"94:83:c4:a0:23:e2",
        "color":"tab:blue"
    },
    "spitz1":{
        "mac":"94:83:c4:a0:21:9a",
        "color":"tab:orange"
    },
    "spitz2":{
        "mac":"94:83:c4:a0:21:4e",
        "color":"tab:green"
    },
    "spitz3":{
        "mac":"94:83:c4:a0:23:2e",
        "color":"tab:brown"
    },
    "spitz4":{
        "mac":"94:83:c4:a0:1e:a2",
        "color":"tab:red"
    },
}

################################################
# Utils

def getNameFromMac(mac):
    for i in routers:
        if routers[i]["mac"] == mac:
            return i
    return "error"

def getMacFromName(name):
    return routers[name]["mac"]

################################################

# Returns array of datastructures of the following kind:
# {'globalTs': 1720175631.07416,
#  'noise': -91,
#  'peerData': {'spitz0': {'rssi': -90,
#                          'txFailsSinceLast': 0,
#                          'txRetriesSinceLast': 0},
#               'spitz1': {'rssi': -97,
#                          'txFailsSinceLast': 0,
#                          'txRetriesSinceLast': 0},
#               'spitz2': {'rssi': -72,
#                          'txFailsSinceLast': 27,
#                          'txRetriesSinceLast': 27},
#               'spitz3': {'rssi': -95,
#                          'txFailsSinceLast': 0,
#                          'txRetriesSinceLast': 0}},
#  'trialNum': 998},
def parseStationDumps(dirname):
    origPwd = os.getcwd()
    me = dirname # expects dirname to be 'spitz0' 'spitz1' ...
    os.chdir(dirname)

    initTxRetry = 0
    initTxFail = 0
    lastTxRetry = 0
    lastTxFail = 0

    initTxRetryValues = {}
    initTxFailValues = {}
    lastTxRetryValues = {}
    lastTxFailValues = {}

    results = []

    for trialFile in sorted(os.listdir()): # Go thru all trial files in the directory
        datapoint = {}

        if 'trial' not in trialFile:
            continue

        trialNum = int(trialFile.split("_")[1])
        globalTs = float(trialFile.split("_")[2].replace(",", "."))
        f = open(trialFile, 'r')
        contents = f.read().split("\n")[:-1]
        f.close()
        
        try:
            localTs = float(contents.pop(0))
            noise = int(contents.pop(-1))

            contents.pop(0) # Remove the - characters 
            contents.pop(-1)
        except Exception as e:
            print(f"[!] Error parsing the file {trialFile}. File may have been prematurely closed")
            traceback.print_exc()
            continue

        # Put trialwide values in our datapoint
        datapoint["noise"] = noise
        datapoint["globalTs"] = globalTs
        datapoint["trialNum"] = trialNum

        # After timestamp noise and - signs are removed what's left is lines of
        # 'peer mac addr' 'rssi' 'tx retries' 'tx fails'
        peerData = {}
        for staLine in contents: # Go thru all peer rssi/txret/txfail lines
            staLine = staLine.split()
            peerMac = staLine[0]
            rssi = int(staLine[1])
            txRetries = int(staLine[2])
            txFails = int(staLine[3])

            # Log first values 
            if (peerMac not in initTxRetryValues):
                initTxRetryValues[peerMac] = txRetries
                initTxFailValues[peerMac] = txFails
                lastTxRetryValues[peerMac] = txRetries
                lastTxFailValues[peerMac] = txFails

            txRetriesSinceBeginning = txRetries - initTxRetryValues[peerMac] 
            txFailsSinceBeginning = txFails - initTxFailValues[peerMac]
            txRetriesSinceLast = txRetries - lastTxRetryValues[peerMac]
            txFailsSinceLast = txFails - lastTxFailValues[peerMac]

            # Log prev iteration values
            lastTxRetryValues[peerMac] = txRetries
            lastTxFailValues[peerMac] = txFails

            # Place them in our end product data structure
            peerData[getNameFromMac(peerMac)] = {
                "rssi":rssi,
                "txFailsSinceLast":txFailsSinceLast,
                "txRetriesSinceLast":txRetriesSinceLast,
                "txFails":txFails,
                "txRetries":txRetries,
                "txFailsInit":initTxFailValues[peerMac],
                "txRetriesInit":initTxRetryValues[peerMac]
            }

            # print(f"{me}-{getNameFromMac(peerMac)} {rssi} beginning {txRetriesSinceBeginning} {txFailsSinceBeginning} | last {txRetriesSinceLast} {txFailsSinceLast} | abs {txRetries} {txFails}")
        datapoint["peerData"] = peerData

        results.append(datapoint)

        # print(me, trialNum, globalTs)

    os.chdir(origPwd)
    return results

# Takes a directory where keys are router names
# i.e. {"spitz0":[...], "spitz1":[...], ...}
# Where every value is an array of data points that $parseStationDumps output
def plotStationDumps(datapoints, figtitle=""):
    fig, axs = plt.subplots(ncols=5, nrows=4)
    # [i.autoscale(enable=True) for i in axs]
    # fig.tight_layout()
    plt.suptitle(f"{figtitle}")

    for ctr, me in enumerate(datapoints): # Go thru all routers
        rssis = {}
        txFails = {}
        txRetries = {}
        noise = []

        for datapoint in datapoints[me]: # Go thru all data points for that router
            noise.append(datapoint['noise'])

            # Populate rssis, txfails, txretries. this is based on if 
            # a connection was made with the peer. If no connection, note it down somehow
            for peer in routers: # Go thru all peers in the datapoint

                if peer not in rssis: # Initialize
                    rssis[peer] = []
                    txFails[peer] = []
                    txRetries[peer] = []

                if peer not in datapoint["peerData"]:
                    # NO CONNECTION WAS MADE
                    rssis[peer].append(-np.Inf)
                    txFails[peer].append(np.Inf)
                    txRetries[peer].append(np.Inf)
                else:
                    # CONNECTION WAS MADE
                    rssis[peer].append(datapoint["peerData"][peer]["rssi"])

                    # txFails[peer].append(datapoint["peerData"][peer]["txFailsSinceLast"])
                    # txRetries[peer].append(datapoint["peerData"][peer]["txRetriesSinceLast"])

                    txFails[peer].append(datapoint["peerData"][peer]["txFails"] - datapoint["peerData"][peer]["txFailsInit"])
                    txRetries[peer].append(datapoint["peerData"][peer]["txRetries"] - datapoint["peerData"][peer]["txRetriesInit"])

        # fig, axs = plt.subplots(ncols=1, nrows=4)
        # [i.autoscale(enable=True) for i in axs]
        # fig.tight_layout()
        # plt.suptitle(f"{me}")

        # Now plot them for _this router_ 
        # Plot noise
        noiseAx = axs[0][ctr]
        noiseAx.set_title(me)
        noiseAx.scatter([i for i in range(0, len(noise))], noise)
        if (ctr == 0):
            noiseAx.set_ylabel("Noise (dBm)")
        
        # Plot rssi
        rssiAx = axs[1][ctr]
        rssiAx.set_ylim(-50, -100)
        for peer in routers:
            rssiAx.scatter([i for i in range(0, len(rssis[peer]))], rssis[peer], c=routers[peer]["color"], s=1, label=peer)
        if (ctr == 0):
            rssiAx.set_ylabel("RSSI (dBm)")

        # Plot Tx Fails
        txFailAx = axs[2][ctr]
        for peer in routers:
            txFailAx.scatter([i for i in range(0, len(txFails[peer]))], txFails[peer], c=routers[peer]["color"], s=1, label=peer)
        txFailAx.set_ylim(bottom=0)
        if (ctr == 0):
            txFailAx.set_ylabel("Tx Fail (Packet)")

        # Plot Tx Retries
        txRetryAx = axs[3][ctr]
        for peer in routers:
            txRetryAx.scatter([i for i in range(0, len(txRetries[peer]))], txRetries[peer], c=routers[peer]["color"], s=1, label=peer)
        txRetryAx.set_ylim(bottom=0)
        if (ctr == 0):
            txRetryAx.set_ylabel("Tx Retry (Packet)")
        txRetryAx.set_xlabel("Trial")

        handles, labels = axs[-1][ctr].get_legend_handles_labels()
    fig.legend(handles, labels, loc='upper right')
    fig.tight_layout()
    # plt.show()
    plt.savefig(f"../{figtitle}_consolidated.png")
    # return axs

def main(dirname):
    print("Dirname", dirname)
    plt.rcParams["figure.figsize"] = (30, 30) # Figure size
    os.chdir(dirname)
    subdirs = sorted(os.listdir("."))

    stationDumpDatapoints = {}
    iperfDatapoints = {}

    # Do the parsing
    for subdir in subdirs:
        if subdir.startswith("."): # omit hidden files which contain run info
            continue

        if "iperf" in subdir:
            print(f"IPERF {os.path.abspath(subdir)}")
        else:
            print(f"STATION DUMP {os.path.abspath(subdir)}")
            parsed = parseStationDumps(subdir)
            stationDumpDatapoints[subdir] = parsed
    # Do the plotting
    plotStationDumps(stationDumpDatapoints, figtitle=dirname.replace("/",""))
    # pprint.pprint(stationDumpDatapoints)

if __name__ == "__main__":
    if (len(sys.argv) != 2):
        print("Error")
        print(usage)
        sys.exit(1)
    main(sys.argv[1])
