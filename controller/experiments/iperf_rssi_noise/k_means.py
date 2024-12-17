#!/usr/bin/env python3

"""
./k_means.py <results dir name> [-k number of centroids]
"""

import sys, os, subprocess, json, traceback, argparse, copy
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

from pprint import pprint
from random import randint
from math import pow, sqrt

from sklearn.cluster import KMeans

import pdb
import pudb

from pandas._libs.tslibs import astype_overflowsafe

colors = ["tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple", "tab:pink", "tab:cyan", "tab:olive", "tab:brown", "tab:gray"]

machines = {
    # Routers below here
    "spitz0":{
        "mac":"94:83:c4:a0:23:e2",
        "color":"tab:blue",
        "type":"router"
    },
    "spitz1":{
        "mac":"94:83:c4:a0:21:9a",
        "color":"tab:orange",
        "type":"router"
    },
    "spitz2":{
        "mac":"94:83:c4:a0:21:4e",
        "color":"tab:green",
        "type":"router"
    },
    "spitz3":{
        "mac":"94:83:c4:a0:23:2e",
        "color":"tab:brown",
        "type":"router"
    },
    "spitz4":{
        "mac":"94:83:c4:a0:1e:a2",
        "color":"tab:red",
        "type":"router"
    },
    # Tx Machines Below here
    "nuc0":{
        "mac":"a0:c5:89:8d:81:64",
        "color":"tab:black",
        "type":"txbox"
    },
}

def shell():
    import IPython
    IPython.embed()

def consolidateParse(dirname, start=None, end=None, weight=2):
    origPwd = os.curdir
    os.chdir(f"{dirname}/consolidated/")
    li = sorted(os.listdir("."))
    trials = []

    # What do i want here? 
    # Lets create a table where each trial looks like: # TODO this is subject to change
    # (SNRs) s0-s1 | s0-s2 | ... | si-sj | PDR

    # So first lets see which machines are there
    # We're now in the results dir. get a list of existing machines in this results dir
    existingMachines = []
    for i in os.listdir(".."):
        if i in machines:
            existingMachines.append(i)
    print(existingMachines)
    
    # Now go thru the files
    numBadTrials = 0
    numTrialFiles = len(os.listdir("."))
    for filename in sorted(os.listdir(".")):
        trial = []
        annotatedTrial = {}

        # Read file
        f = open(filename, "r")
        try:
            jsonContents = json.load(f)
        except Exception as e:
            print(f"Error loading json. {filename}")
            traceback.print_exc()
            f.close()
            continue
        f.close()

        trialNum = jsonContents["trial"]

        # If start or end limits are set
        if (start != None and trialNum < start) or (end != None and trialNum > end):
            continue
        
        # Iperf
        iperfErrored = False
        for iperf in jsonContents["iperf"]:
            if "error" in iperf["results"]:
                print(f"File {filename} has error {iperf['results']['error']} ")
                # badIperfIndices.append(trialNum)
                iperfErrored = True
                continue
            results = iperf["results"]["end"]
            route = iperf["route"]
            numHops = len(route)

            lostPercent = results["sum"]["lost_percent"]

        if iperfErrored:
            numBadTrials += 1
            continue

        # Passives
        for me in sorted(existingMachines):
            for peer in sorted(existingMachines):
                if (me == peer):
                    continue
                # if (jsonContents["station_dump"][me] == {}) or (me == peer):
                #     continue
                # pdb.set_trace()
                # print(me, peer, jsonContents["station_dump"][me]["station_dump"][peer]["snr"])
                # annotatedTrial.extend({"me":me, "peer":peer, "snr":jsonContents["station_dump"][me]["station_dump"][peer]["snr"]})
                try:
                    trial.append(jsonContents["station_dump"][me]["station_dump"][peer]["snr"])
                except:
                    trial.append(-50)

        # Append our PDR to the end of the trial datapoint?
        # Should we also weight it more so that points separate more based on lost percent?
        weightedLostPercent = lostPercent ** weight
        # trial.append(weightedLostPercent)
        trial.append(lostPercent)
        
        # Put em all together
        trials.append(trial)

    # pprint(trials)
    os.chdir(origPwd)
    print(f"{numBadTrials} / {numTrialFiles} trials are bad")
    return trials

def getDistance(centroid, trial):
    numFields = len(centroid)
    innerProduct = 0
    for idx, val in enumerate(centroid):
        innerProduct += pow((centroid[idx] - trial[idx]), 2)
    return sqrt(innerProduct)

# Takes an array of vectors of size n 
def calculateCentroid(cluster):
    clusterSize = len(cluster)
    vectorSize = len(cluster[0])
    centroid = [0] * vectorSize
    for p in cluster:
        centroid = np.add(centroid, p)
    centroid = np.divide(centroid, clusterSize)
    return list(centroid)

def runKmeansNaive(trials, k=5, convergenceTolerence=0.0001, numIterations=100, randomInitialCentroids=False):
    # First find the number of fields in our datapoints
    numFields = len(trials[0])

    # Initialize our centroids # TODO look at methods to choose an init centroid
    centroids = []

    if randomInitialCentroids: 
        # fully Random centroids
        centroids = [[randint(-20, 40) for i in range(0, numFields)] for j in range(0, k)]
    else: 
        # Pick one of our trials randomly as a centroid
        for i in range(0, k):
            centroids.append(trials[randint(0, len(trials)-1)])

    # Loop until convergence or numIter is reached
    convergence = False
    iter = 0
    
    print(f"K means on {len(trials)} trials, k={k}")

    while not convergence:
        print(f"K means iter {iter}")
        # Clear prev clusters
        clusters = [[] for i in range(0, len(centroids))]

        # Assign each point to the "closest" centroid
        for trial in trials:
            distances = [getDistance(centroid, trial) for centroid in centroids]
            clusterIdx = np.argmin(distances)
            clusters[clusterIdx].append(trial)
        
        [print(f"Cluster {i} len {len(clusters[i])}") for i,_ in enumerate(clusters)]
            
        # Calculate new centroids
        # The standard implementation uses the mean of all points in a cluster to determine the new centroid
        newCentroids = [calculateCentroid(cluster) for cluster in clusters]

        # Check for convergence
        diff = np.sum(np.subtract(centroids, newCentroids))
        # pdb.set_trace()
        print(f"Centroid diff {diff}")
        centroids = newCentroids
        if abs(diff) < convergenceTolerence:
            convergence = True
            print(f"K means algo reached convergence at {iter} iterations with diff {diff}. Breaking")
            break

        iter += 1
        if (iter == numIterations):
            print(f"K means algo reached {iter} iterations. Breaking")
            break

    return (centroids, clusters)

def analyzeClusters(centroids, clusters, weight=2):
    print(f"Analyzing {len(centroids)} clusters")
    [print(f"Cluster: {i} length: {len(clusters[i])} lost percent: {c[-1] ** (1/weight)}") for i, c in enumerate(centroids)]
    import IPython
    IPython.embed()

def runKmeansScikit(trials, weights=None, k=5, max_iter=1000):
    kmeans = KMeans(n_clusters=k, random_state=0, max_iter=max_iter)
    clusters = kmeans.fit(trials)
    return clusters

def analyzeNpClusters(clusters, testData):
    k = clusters.n_clusters
    prediction = clusters.predict(testData)
    print(f"Intertia {clusters.inertia_}")

    for i in range(0, k):
        print(f"Centroid {i} {list(clusters.labels_).count(i)}")

    print("Predictions:")
    for i in range(0, k):
        print(f"Centroid {i} {list(prediction).count(i)}")

    return prediction

def analyzeTrims(labels, orig, trimmed, k):
    origLossPercents = orig[:,-1]
    clusters = [[] for i in range(0, k)]
    lossPercents = [[] for i in range(0, k)]
    # fig, ax = plt.subplots()
    for idx, label in enumerate(labels):
        clusters[label].append(orig[idx])
        lossPercents[label].append(origLossPercents[idx])
        # ax.scatter(label, origLossPercents[idx], c=colors[label])
    # plt.show()

def main(dirname, k=5):
    print(f"Dirname {dirname} k {k}")

    # What do i want here? 
    # 1) divide trials by percentage done
    trials = consolidateParse(dirname)

    trainPercent = 50
    trainAmount = int(len(trials) * trainPercent / 100)
    trainTrials = trials[0:trainAmount]
    testTrials = trials[trainAmount:]

    # 2) set weights
    weights = np.ones(len(trials[0]))
    weights[-1] = 3

    # 3) Convert trials into numpy arrays
    npTrainTrials = np.array(trainTrials)
    npTestTrials = np.array(testTrials)
    npWeightedTrainTrials = np.array(np.multiply(trainTrials, weights))
    npWeightedTestTrials = np.array(np.multiply(testTrials, weights))

    # 4) Now we have trials divided into train and test and we have separate weighted trials
    #    Now is the time for k means
    kmeans = KMeans(n_clusters = k, random_state = 0, max_iter = 1000)
    clusters = kmeans.fit(npTrainTrials) 

    weightedKmeans = KMeans(n_clusters = k, random_state = 0, max_iter = 1000)
    weightedClusters = weightedKmeans.fit(npWeightedTrainTrials)

    # 5) Now we have our clusters and centroids, now what?
    #    Now do a prediction
    print("Unweighted clusters")
    clustersPrediction = analyzeNpClusters(clusters, npTestTrials)

    print()

    print("Weighted clusters")
    weightedClustersPrediction = analyzeNpClusters(weightedClusters, npWeightedTestTrials)

    # 6) Trim the last column off of the feature matrices
    trimmedClusters = copy.deepcopy(clusters)
    trimmedClusters.cluster_centers_ = np.delete(trimmedClusters.cluster_centers_, np.s_[-1], axis=1)
    trimmedClusters.n_features_in_ -= 1

    trimmedWeightedClusters = copy.deepcopy(weightedClusters)
    trimmedWeightedClusters.cluster_centers_ = np.delete(trimmedWeightedClusters.cluster_centers_, np.s_[-1], axis=1)
    trimmedWeightedClusters.n_features_in_ -= 1

    trimmedNpTestTrials = npTestTrials
    trimmedNpTestTrials = np.delete(trimmedNpTestTrials, np.s_[-1], axis=1)

    trimmedNpWeightedTestTrials = npWeightedTestTrials
    trimmedNpWeightedTestTrials = np.delete(trimmedNpWeightedTestTrials, np.s_[-1], axis=1)

    # Sanity check to make sure cluster labels are the same
    if (np.sum(clusters.labels_ == trimmedClusters.labels_) != len(clusters.labels_)):
        print("Labels of clusters and trimmedClusters do not match")

    # 7) Now test with the trimmed versions
    print()
    print("Trimmed Unweighted Clusters")
    trimmedClustersPrediction = analyzeNpClusters(trimmedClusters, trimmedNpTestTrials)

    print()

    print("Trimmed Weighted Clusters")
    trimmedWeightedClustersPrediction = analyzeNpClusters(trimmedWeightedClusters, trimmedNpWeightedTestTrials)

    analyzeTrims(trimmedClustersPrediction, npTestTrials, trimmedNpTestTrials, k)

    analyzeTrims(trimmedWeightedClustersPrediction, npWeightedTestTrials, trimmedNpWeightedTestTrials, k)
    
    # Hmmmmmmmmmmmmmmmmmmm
    # That didnt really go too far now did it? 
    # New trial
    # 1) Fit our clusters based on packet loss
    trainLosses = np.squeeze(np.array(np.mat(trainTrials)[:,-1]))
    # trainLosses = np.power(trainLosses, 2)
    lossKmeans = KMeans(n_clusters = k, random_state = 0, max_iter = 1000)
    lossCentroids = lossKmeans.fit(trainLosses.reshape(-1,1))
    lossCentroidsLabels = lossCentroids.labels_
    lossClusters = [[] for i in range(0, k)]
    for i, trial in enumerate(trainTrials):
        label = lossCentroidsLabels[i]
        lossClusters[label].append(trial)

    # 2) Above "centroids" are based on only the loss percent column
    #    Below we have the respective SNR points
    centroids = np.squeeze([np.mean(i, axis=0) for i in lossClusters])
    trimmedCentroids = np.delete(centroids, np.s_[-1], axis=1)

    # 3) Copy over our old kmeans object and replace fields in it
    snrCentroids = copy.deepcopy(lossCentroids)
    snrCentroids.cluster_centers_ = trimmedCentroids
    snrCentroids.n_features_in_ = len(trimmedCentroids[0])

    # 4) Now let's test this new kmeans using a test set
    print()
    print("SNR Kmeans test")
    snrPrediction = analyzeNpClusters(snrCentroids, trimmedNpTestTrials)

    analyzeTrims(snrPrediction, npTestTrials, trimmedNpTestTrials, k)
    snrClusters = [[] for i in range(0, k)]
    for i, trial in enumerate(npTestTrials):
        label = snrPrediction[i]
        snrClusters[label].append(trial)

    import IPython
    IPython.embed()
    # shell()

    # 5) welp. this didnt go nowhere. time to give up

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dirname", help="Results dirname")
    parser.add_argument("-k", type=int, default=3, help="K centroids")
    args = parser.parse_args() 

    dirname = args.dirname
    k = args.k
    main(dirname, k)
