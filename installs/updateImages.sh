#!/bin/bash
#------------------------------------------------------------------
# Script to deploy AKS based Jmeter test framework
# 
# Authors: Pete Grimsdale
#------------------------------------------------------------------

# Display usage information and exit
display_help() {
    echo "Usage: $0 [option...]" >&2
    echo
    echo "   This script provides the ability to update the container images "
    echo "   A updated image version will be pushed to the acr in the resource group provided"
    echo "   Use update.sh -g <resource group name    "
    echo "   Note: This should be the resource group containing the acr being used for the framework"
    exit 0
}

# SubscriptionId of the current subscription
subscriptionId=$(az account show --query id --output tsv)
logfile=./testfwklog
exec > >(tee -ai $logfile) 2>&1

while getopts hg:n: opt; do
                case ${opt} in
                    (h)
                        display_help
                        ;;
                    (g)
                        resourceGroup=$OPTARG
                        ;;
                    (n)
                        aksName=$OPTARG
                        ;;
                    (*)
                        display_help
                        ;;
                    (\?)
                        echo "Invalid Option: -$OPTARG" 1>&2
                        display_help
                        ;;
                    (:)
                        echo "Invalid Option: -$OPTARG requires an argument" 1>&2
                        display_help
                        ;;
                esac
        done

#check parameters
if [[ -z ${resourceGroup}  ]] || [[ -z ${aksName}  ]] ;then
    echo "ERROR:Resource Group and AKS name must be provided"
    exit 1
fi

echo "The resource group to use is: $resourceGroup and AKS name is: $aksName"

#Get the container registry
acrName=$(az acr list -g $resourceGroup -o tsv --query [].name)
echo "INFO:building updated images and pushing to [ $acrName ]"

#version number
version=`cat VERSION`
echo "INFO: $version will be added to acr"

#Update slave container
echo "INFO:building updated jmeter slave container and pushing to [ $acrName ]"
az acr build -t jmeterslave:latest -t jmeterslave:$version -f ../slave/Dockerfile  -r $acrName .
if [ $? -ne 0 ]
then
    echo "ERROR:Failed to build and push slave error: '${?}'"
    exit 1
else
    echo "INFO:jmeter slave update container completed...."
fi

#update master container
echo "INFO:building updated jmeter master container and pushing to [ $acrName ]"
az acr build -t jmetermaster:latest -t jmetermaster:$version -f ../master/Dockerfile  -r $acrName .
if [ $? -ne 0 ]
then
    echo "ERROR:Failed to build and push master error: '${?}'"
    exit 1
else
    echo "INFO:jmeter master update container completed...."
fi

echo "INFO:  update of images completed"

#update deployment
#get creds
if az aks get-credentials --resource-group $resourceGroup --name $aksName --overwrite-existing &>/dev/null; then
    nodes=$(kubectl get nodes |awk '/aks-nodepool/ {print $1}')
        if [[ -z {$nodes} ]]; then
           echo "issue with kubectl setup"
           exit 1
        else
            echo "INFO: kubectl available...."
        fi
else
    echo "ERROR: Cannot connect to AKS cluster $aksName . Please check the cluster name provided is correct"
    exit 1
fi