#!/bin/bash

# Remove Cognito service property from Elasticsearch
#echo $1
sed -i '/Cognito/,+2 d' $1
