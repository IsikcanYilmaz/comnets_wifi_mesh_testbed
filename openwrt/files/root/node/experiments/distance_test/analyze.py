#!/usr/bin/env python3

import sys, os, subprocess, json
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

"""
Usage: ./analyze.py

Put this script in the results file. It depends on bw_$BW_tx_$TX_distance_$DIST.txt json files and tx_$TX_dist_$DIST_sta_dump.txt station dump text files.

"""

res = subprocess.run(["ls"], stdout=subprocess.PIPE)
filenames = res.stdout.decode("utf-8").replace("\n", " ")[:-1].split(" ")

staDump = []

for i in filenames:
    if "_sta_dump" in i:
        filenameArr = i[:-4].split("_")
        tx = int(filenameArr[1])
        dist = int(filenameArr[3])
        pktlosspercent = receivedbps = sentbps = -1

        with open(f"bw_200_tx_{tx}_distance_{dist}.txt") as f:
            d = json.load(f)
            pktlosspercent = d["end"]["sum_received"]["lost_percent"]
            receivedbps = d["end"]["sum_received"]["bits_per_second"]
            sentbps = d["end"]["sum_sent"]["bits_per_second"]

        # print(tx, dist)
        f = open(i, "r")
        lines = f.readlines()
        f.close()
        for l in lines:
            if "signal" in l and "avg" not in l and "last" not in l:
                sig = l.replace("\t", "").split(" ")[2]
                print(tx, dist, sig)
                staDump.append({"Distance":dist, "TxPower":tx, "Signal":sig, "Bits Per Second (R)":receivedbps, "Bits Per Second (S)":sentbps, "Loss %":pktlosspercent})
                break

    elif "distance" in i:
        pass

# [print(i) for i in sta_dumps]
# print(sorted(sta_dumps))

# staDumpDf = pd.DataFrame(columns=["Distance", "TxPower", "Signal"])
staDumpDf = pd.DataFrame(staDump)
staDumpDf = staDumpDf.sort_values(by=["TxPower"])
print(staDumpDf.loc[staDumpDf['Distance'] == 32].to_string())
