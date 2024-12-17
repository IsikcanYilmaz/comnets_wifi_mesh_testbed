#!/usr/bin/env python3

import pandas as pd
import numpy as np
import shap
import matplotlib.pyplot as plt
import pdb
import argparse, os, traceback, json
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomTreesEmbedding, GradientBoostingRegressor
from sklearn.metrics import classification_report, accuracy_score
from sklearn.svm import SVC
from sklearn.neural_network import MLPClassifier, MLPRegressor
from imblearn.over_sampling import SMOTE
from scipy import stats


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
            # trial.append(jsonContents["station_dump"][me]["noise"])
            for peer in sorted(existingMachines):
                if (me == peer):
                    continue
                try:
                    # SNR
                    # trial.append(jsonContents["station_dump"][me]["station_dump"][peer]["snr"])
                    # RSSI
                    trial.append(jsonContents["station_dump"][me]["station_dump"][peer]["rssi"])
                    # Noise
                    # trial.append(jsonContents["station_dump"][me]["noise"])
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

def MLPClassifierTrainAndTest(Xtrain, Ytrain, classTrain, Xtest, Ytest, classTest, hidden_layer_sizes=(5,2)):
    alpha = 1e-5
    max_iter = 10000
    clf = MLPClassifier(solver='lbfgs', alpha=alpha, hidden_layer_sizes=hidden_layer_sizes, random_state=1, max_iter=max_iter)
    clf.fit(Xtrain, classTrain)
    pred = clf.predict(Xtest)

    uneqCount = 0
    for i, p in enumerate(pred):
        if (p != classTest[i]):
            uneqCount += 1

    print(f"Hidden layer sizes {hidden_layer_sizes} {uneqCount}/{len(pred)} misclassifications")
    print("Score ", clf.score(Xtest, classTest))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dirname")
    parser.add_argument("--train-percent")
    args = parser.parse_args()
    parsed = consolidateParse(args.dirname)

    train_percent = int(args.train_percent) if (args.train_percent) else 80
    test_percent = 100 - train_percent

    train_amount = int(len(parsed) * train_percent / 100)
    test_amount = len(parsed) - train_amount

    npParsed = np.array(parsed)

    npTrain = npParsed[0:train_amount]
    npTest = npParsed[train_amount:]

    Xtrain = npTrain[:,:-1]
    Ytrain = npTrain[:,-1]
    classTrain = [] # Label our PDR values

    classes = [ 10, 20, 30, 40, 50, 100]

    for idx, i in enumerate(Ytrain):
        for j in range(0,len(classes)):
            if i < classes[j]:
                classTrain.append(j)
                break

    print(f"Training data")
    for j in range(0, len(classes)):
        print(f"Class {j} < {classes[j]} count {classTrain.count(j)}")

    Xtest = npTest[:,:-1]
    Ytest = npTest[:,-1]
    classTest = []

    for i in Ytest:
        for j in range(0,len(classes)):
            if i < classes[j]:
                classTest.append(j)
                break

    print(f"Test data")
    for j in range(0, len(classes)):
        print(f"Class {j} < {classes[j]} count {classTest.count(j)}")

    # Multi Layer Perceptron
    hidden_trials = [(5,5)]
    for i in hidden_trials:
        MLPClassifierTrainAndTest(Xtrain, Ytrain, classTrain, Xtest, Ytest, classTest, hidden_layer_sizes=i)

