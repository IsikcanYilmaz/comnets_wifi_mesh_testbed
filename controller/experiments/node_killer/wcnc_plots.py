#!/usr/bin/env python3

import sys, os, argparse, pdb, json, pprint
import matplotlib.pyplot as plt

# BLANKS
# What do i want here?
# these plots should show the amount of ctrl messaging
blankruns = {}
runs = {}
floodruns = {}

def blank_wcnc():
    global blankruns
    for sweep in os.listdir():
        if "blank" not in sweep:
            continue
        print(sweep)
        os.chdir(sweep)
        runtime = 60 # seconds
        for dir in os.listdir():
            try:
                f = open(f"{dir}/node_killer.json", "r")
            except Exception as e:
                print(f"{dir}/node_killer.json not found!")
                continue
            nodeKiller = json.load(f)
            f.close()
            # From node killer i want:
            # reconnection_time
    
            try:
                f = open(f"{dir}/total_batman_stats.json", "r")
            except Exception as e:
                print(f"{dir}/total_batman_stats.json not found!")
                continue
            totals = json.load(f)
            f.close()
            # From totals I want:
            # mgmt_tx mgmt_tx_bytes forward_pkts forward_bytes tx tx_bytes (for blank)

            f = open(f"{dir}/.config", "r")
            config = json.load(f)
            f.close()
            # From config I need ogm interval

            ogmInterval = int(config["ogm_interval"])
            if ogmInterval not in blankruns:
                blankruns[ogmInterval] = []

            blankruns[ogmInterval].append( {
                "reconnection_time":nodeKiller["reconnection_time"],
                "mgmt_tx":totals["mgmt_tx"],
                "mgmt_tx_bytes":totals["mgmt_tx_bytes"],
                "forward_pkts":totals["forward_pkts"],
                "forward_bytes":totals["forward_bytes"],
                "tx":totals["tx"],
                "tx_bytes":totals["tx_bytes"]
            })
        os.chdir("..")

def plot_all_blank_wcnc():
    global blankruns
    font = {'family' : 'normal' , 'size' : 12}
    plt.rc('font', **font)
    
    fig, axs = plt.subplots(2,1)
    
    axs[0].grid(True, which="both")
    axs[1].grid(True, which="both")
    
    # pdb.set_trace()

    reconnection_time_averages = {}
    mgmt_tx_averages = {}
    for ogm in sorted(blankruns):
        reconnSum = 0
        mgmtTxSum = 0
        for i in blankruns[ogm]:
            reconnSum += i["reconnection_time"]
            mgmtTxSum += i["mgmt_tx"]
        reconnection_time_averages[ogm] = (reconnSum / len(blankruns[ogm]))
        mgmt_tx_averages[ogm] = (mgmtTxSum / len(blankruns[ogm]))

    axs[0].plot([i/1000 for i in sorted(blankruns)], [reconnection_time_averages[i] for i in sorted(blankruns)], linewidth=2)
    axs[1].plot([i/1000 for i in sorted(blankruns)], [mgmt_tx_averages[i] for i in sorted(blankruns)], linewidth=2)

    axs[0].set_ylabel("Reconnection Time (s)")
    axs[1].set_ylabel("Management Packets")
    axs[1].set_xlabel("Management Packet Interval (s)")

    # Scatters
    for j in range(0, len(blankruns[100])):
        try:
            axs[0].scatter([i/1000 for i in sorted(blankruns)], [blankruns[i][j]["reconnection_time"] for i in sorted(blankruns)], color="blue", s=10)
            axs[1].scatter([i/1000 for i in sorted(blankruns)], [blankruns[i][j]["mgmt_tx"] for i in sorted(blankruns)], color="blue", s=10)
        except Exception as e:
            continue

    # plt.show()
    plt.savefig("blanks.svg")

def plot_blank_wcnc():
    global blankruns

    font = {'family' : 'normal' , 'size' : 12}
    plt.rc('font', **font)
    
    fig, axs = plt.subplots(2,1)
    fig.suptitle("Connection Recovery Time vs. Control Overhead - \nNetwork Idle")

    axs[0].grid(True, which="both")
    axs[0].plot([i/1000 for i in sorted(blankruns)], [blankruns[i]["reconnection_time"] for i in sorted(blankruns)])
    axs[0].set_ylabel("Reconnection Time (s)")

    axs[1].grid(True, which="both")
    axs[1].set_yscale("log")
    axs[1].plot([i/1000 for i in sorted(blankruns)], [blankruns[i]["mgmt_tx"] for i in sorted(blankruns)])
    axs[1].set_ylim(0,10000)
    axs[1].set_ylabel("Management Packets")
    axs[1].set_xlabel("Management Packet Interval (s)")

    # plt.show()
    plt.savefig("blanks.png")

def traffic_wcnc():
    global runs
    os.chdir("to_plot")
    runtime = 30 # seconds
    for dir in os.listdir():
        f = open(f"{dir}/node_killer.json", "r")
        nodeKiller = json.load(f)
        f.close()
        # From node killer i want:
        # reconnection_time

        f = open(f"{dir}/total_batman_stats.json", "r")
        totals = json.load(f)
        f.close()
        # From totals I want:
        # mgmt_tx mgmt_tx_bytes forward_pkts forward_bytes tx tx_bytes (for blank)

        f = open(f"{dir}/.config", "r")
        config = json.load(f)
        f.close()
        # From config I need ogm interval

        f = open(f"{dir}/iperf_server_spitz0_spitz3.json")
        iperf = json.load(f)
        f.close()
        # From iperf i need
        # maaaybe iperf received bytes?

        ogmInterval = int(config["ogm_interval"])
        runs[ogmInterval] = {
            "reconnection_time":nodeKiller["reconnection_time"],
            "mgmt_tx":totals["mgmt_tx"],
            "mgmt_tx_bytes":totals["mgmt_tx_bytes"],
            "forward_pkts":totals["forward_pkts"],
            "forward_bytes":totals["forward_bytes"],
            "tx":totals["tx"],
            "tx_bytes":totals["tx_bytes"],
            "iperf_received_bytes":iperf["end"]["sum_received"]["bytes"],
            "iperf_received_packets":iperf["end"]["sum_received"]["packets"],
            "iperf_received_lost":iperf["end"]["sum_received"]["lost_percent"],
        }
    os.chdir("..")

def plot_traffic_wcnc():
    global runs

    font = {'family' : 'normal' , 'size' : 12}
    plt.rc('font', **font)
    plt.rcParams.update({'legend.fontsize':9})
    
    fig, axs = plt.subplots(2,1)
    fig.tight_layout()
    # fig.suptitle("Sent Network Packets, Aggregated")

    x = [str(i/1000) for i in sorted(runs)]

    axs[0].grid(True, which="both")
    axs[1].grid(True, which="both")

    plt.legend(fontsize=5)

    axs[0].bar(x, [runs[i]["tx"] for i in sorted(runs)], label="Payload")
    axs[0].bar(x, [runs[i]["mgmt_tx"] for i in sorted(runs)], bottom=[runs[i]["tx"] for i in sorted(runs)], label="Management")
    axs[0].bar(x, [runs[i]["forward_pkts"] for i in sorted(runs)], bottom=[runs[i]["tx"] + runs[i]["mgmt_tx"] for i in sorted(runs)], label="Forwarded")
    axs[0].legend(loc="upper right")
    # axs[0].set_xlabel("Management Packet Interval (s)")
    axs[0].set_ylabel("Packets Sent")

    axs[1].bar(x, [runs[i]["tx_bytes"] for i in sorted(runs)], label="Payload Bytes")
    axs[1].bar(x, [runs[i]["mgmt_tx_bytes"] for i in sorted(runs)], bottom=[runs[i]["tx_bytes"] for i in sorted(runs)], label="Management Bytes")
    axs[1].bar(x, [runs[i]["forward_bytes"] for i in sorted(runs)], bottom=[runs[i]["tx_bytes"] + runs[i]["mgmt_tx_bytes"] for i in sorted(runs)], label="Forwarded Bytes")
    # axs[1].legend(loc="upper right")
    axs[1].set_xlabel("Management Packet Interval (s)")
    axs[1].set_ylabel("Bytes Sent")

    # plt.show()
    plt.savefig("traffic_packets.svg",bbox_inches='tight', dpi=600)

def plot_traffic_reconnect_wcnc():
    global runs

    font = {'family' : 'normal' , 'size' : 12}
    plt.rc('font', **font)
    
    fig, axs = plt.subplots(2,1)
    fig.suptitle("Connection Recovery Time vs. Control Overhead - \nIperf Traffic")

    axs[0].grid(True, which="both")
    axs[0].plot([i/1000 for i in sorted(runs)], [runs[i]["reconnection_time"] for i in sorted(runs)])
    axs[0].set_ylabel("Reconnection Time (s)")

    axs[1].grid(True, which="both")
    axs[1].set_yscale("log")
    axs[1].plot([i/1000 for i in sorted(runs)], [runs[i]["mgmt_tx"] for i in sorted(runs)])
    axs[1].set_ylim(0,10000)
    axs[1].set_ylabel("Management Packets")
    axs[1].set_xlabel("Management Packet Interval (s)")

    # plt.show()
    plt.savefig("traffic_reconnect.svg")

def flood_wcnc():
    global floodruns

def plot_flood_wcnc():
    pass

# blank_wcnc()
# plot_all_blank_wcnc()
# plot_blank_wcnc()
# traffic_wcnc()
# plot_traffic_wcnc()
# plot_traffic_reconnect_wcnc()
flood_wcnc()
