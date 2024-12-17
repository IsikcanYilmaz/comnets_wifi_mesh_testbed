#!/usr/bin/env python3

import sys
import json
from pymongo import MongoClient

# Takes the following arguments:
# - MONGO_HOST, MONGO_PORT, MONGO_DB, data_file, collection
# In this order

MONGO_HOST = sys.argv[1]
MONGO_PORT = int(sys.argv[2])
MONGO_DB   = sys.argv[3]
data_file  = sys.argv[4]
collection = sys.argv[5]

# print(MONGO_HOST, MONGO_PORT, MONGO_DB, data_file, collection)

try:
    with open(data_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error loading JSON data from data_file: {e}")
    sys.exit(1)

client = MongoClient(MONGO_HOST, MONGO_PORT)
db = client[MONGO_DB]
coll = db[collection]

try:
    coll.insert_one(data)
except Exception as e:
    print(f"Error inserting data into MongoDB collection collection: {e}")
    sys.exit(1)
