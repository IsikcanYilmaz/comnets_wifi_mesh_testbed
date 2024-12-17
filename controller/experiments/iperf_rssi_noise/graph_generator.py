#!/usr/bin/env python3
"""This code is for generating graphs of packet loss graph from entire dataset and RSSI graph from all routers. For running this one, gave folder where all dataset is avialable and output folder name where output graph need to store. 
The folder structure is very important in this code, if there is any change in folders update here!!! """

import os
import json
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime
import sys

def extract_packet_loss(file_path): #to get packetloss and timestamp
    with open(file_path, 'r') as f:
        data = json.load(f)
    if 'sum_received' in data['end']:
        packet_loss = data['end']['sum_received']['lost_percent']
    else:
        packet_loss = None
    file_name = os.path.basename(file_path)
    timestamp = file_name.split('_')[2].split(',')[0]  
    return int(timestamp), packet_loss    

def process_rssi_file(file_path): #return rssi value, mac addr, datetime in tuples
    with open(file_path, 'r') as f:
        lines = f.readlines()
    timestamp = float(lines[0].strip())
    datetime_obj = datetime.utcfromtimestamp(timestamp)  
    data = [] 
    for line in lines[2:-1]:
        parts = line.strip().split()
        if len(parts) == 4:
            mac, rssi, tx_fail, tx_retry = parts
            rssi = int(rssi)
            if rssi != 0:  # Exclude RSSI value of 0
                data.append((datetime_obj, mac, rssi))
    return data

def process_rssi_folder(folder_path): # to iterate over all files
    data = []
    for file_name in os.listdir(folder_path):
        file_path = os.path.join(folder_path, file_name)
        data.extend(process_rssi_file(file_path))
    return data

def main(data_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    packet_loss_dir = os.path.join(data_dir, 'iperf_spitz0_spitz3')
    packet_loss_data = []
    for file_name in os.listdir(packet_loss_dir):
        if file_name.startswith('trial_'):
            file_path = os.path.join(packet_loss_dir, file_name)
            timestamp, packet_loss = extract_packet_loss(file_path)
            if packet_loss is not None:  # Only add data if packet_loss is not None
                packet_loss_data.append((timestamp, packet_loss))

    df_packet_loss = pd.DataFrame(packet_loss_data, columns=['timestamp', 'packet_loss'])
    df_packet_loss['datetime'] = pd.to_datetime(df_packet_loss['timestamp'], unit='s')
    df_packet_loss.sort_values(by='datetime', inplace=True)

    plt.figure(figsize=(10, 6))
    plt.scatter(df_packet_loss['datetime'], df_packet_loss['packet_loss'], color='b')
    plt.xlabel('Datetime')
    plt.ylabel('Packet Loss (%)')
    plt.title('Packet Loss Over Time')
    plt.grid(True)
    plt.xticks(rotation=45)
    plt.tight_layout()

    packet_loss_output_path = os.path.join(output_dir, 'packet_loss.png')
    plt.savefig(packet_loss_output_path)
    plt.close()

    print(f"Packet loss plot saved as {packet_loss_output_path}")

    mac_to_name = {
        "94:83:c4:a0:23:e2": "spitz0",
        "94:83:c4:a0:21:9a": "spitz1",
        "94:83:c4:a0:21:4e": "spitz2",
        "94:83:c4:a0:23:2e": "spitz3",
        "94:83:c4:a0:1e:a2": "spitz4"
    }

    colors = {
        "spitz0": "red",
        "spitz1": "orange",
        "spitz2": "blue",
        "spitz3": "green",
        "spitz4": "pink"
    }

    for folder_name in ["spitz0", "spitz1", "spitz2", "spitz3", "spitz4"]:
        rssi_folder_path = os.path.join(data_dir, folder_name)
        rssi_data = process_rssi_folder(rssi_folder_path)

        df_rssi = pd.DataFrame(rssi_data, columns=['datetime', 'mac', 'rssi'])

        count_dict = {router: 0 for router in mac_to_name.values()}

        plt.figure(figsize=(10, 6))
        for mac, group in df_rssi.groupby('mac'):
            router_name = mac_to_name[mac]
            count_dict[router_name] = len(group)
            plt.scatter(group['datetime'], group['rssi'], label=router_name, color=colors[router_name])
        plt.xlabel('Datetime')
        plt.ylabel('RSSI')
        plt.title(f'RSSI Values Over Time - {folder_name}')
        plt.legend(loc='upper right')
        plt.ylim(-100, 0)
        plt.grid(True)
        plt.xticks(rotation=45)
        plt.tight_layout()

        rssi_output_path = os.path.join(output_dir, f'aswin_rssi_{folder_name}.png')
        plt.savefig(rssi_output_path)
        plt.close()

        print(f"RSSI plot saved as {rssi_output_path}")
        print(f"Point counts for {folder_name}: {count_dict}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python graph_generator.py <data_directory> <output_directory>")
        sys.exit(1)
    
    data_directory = sys.argv[1]
    output_directory = sys.argv[2]
    main(data_directory, output_directory)

