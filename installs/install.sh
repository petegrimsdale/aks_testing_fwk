#!/bin/bash
#------------------------------------------------------------------
# Script to deploy AKS based Jmeter test framework
# 
# Authors: Pete Grimsdale
#------------------------------------------------------------------

# Variables

# SubscriptionId of the current subscription
subscriptionId=$(az account show --query id --output tsv)

#ACR Name to be used
acrName="testframeworkacr"
############################################################################
#common functions
############################################################################

# Check if the resource group already exists
rg_check() {
    rg=$resourceGroup

    echo "Checking if [ $resourceGroup ] resource group actually exists in the [$subscriptionId] subscription..."
    if [ $command == "install" ]; then
        if ! az group show --name "$resourceGroup" &>/dev/null; then
            echo "No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
            echo "Creating [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription..."

            # Create the resource group
            if az group create --name "$resourceGroup" --location "$location" 1>/dev/null; then
                echo "[ $resourceGroup ] resource group successfully created in the [ $subscriptionId ] subscription"
            else
                echo "Failed to create [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription"
                exit 1
            fi
        else
            echo "[ $resourceGroup ] resource group already exists in the [ $subscriptionId ] subscription"
        fi
    else
        if ! az group show --name "$resourceGroup" &>/dev/null; then
            echo "No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
            echo ""
        else
            echo "[ $resourceGroup ] resource group already exists in the [ $subscriptionId ] subscription"
            echo ""
        fi
    fi
}


# Display usage information and exit
display_help() {
    echo "Usage: $0 [option...]" >&2
    echo
    echo "   command    install / validate"
    echo "   -g		Resource Group Name."
    echo "   -l		Location."
    echo "   -s		spname"
    echo
    echo "   command    delete"
    echo "   -g		Resource Group Name."
    echo "   -s		spname"
    exit 1
}

#sp check
sp_check() {
spId=$(az ad sp list --display-name $spname -o tsv --query [].appId)
if [[ -z ${spId}  ]]; then
    echo "Service Principal - $spname a does not exist...."
    echo ""
else
    echo "Service Principal - $spname already exists...."
    echo "please choose altenative name"
fi
}

# kubectl check
kube_check() {
    echo "checking if kubectl is present"

    if ! hash kubectl 2>/dev/null
        then
            echo "'kubectl' was not found...."
            echo "Kindly ensure that you can acces an existing kubernetes cluster via kubectl / install kubectl"
    else
        echo "kubectl was successfully found..."
        echo ""
    fi
}

#check AKS cluster
cluster_check() {
    echo "checking access to AKS cluster...."
    if ! az aks get-credentials -g "$resourceGroup" -n jmeteraks &>/dev/null; then
        echo "No jmeteraks cluster exists in the resource group [ $resourceGroup ]...."
        echo ""
    else
        echo "Jmeteraks cluster exists in [ $resourceGroup ]..."
        echo ""
    fi
}

# Clean up on script failure
# remove resource group and SP
clean_up() {

    #remove resource group
    if ! az group show --name "$resourceGroup" &>/dev/null; then
        echo "No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
        echo ""
    else
        echo "deleting resource group..."
        echo ""
        if az group delete --name "$resourceGroup" -y  1>/dev/null; then
            echo "[ $resourceGroup ] resource group successfully deleted from the [ $subscriptionId ] subscription"
            echo ""
        else
            echo "Failed to delete [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription.  Please delete manually"
            exit 1
        fi
    fi

#remove the SP
    #get the sp id
    servicePrincipalId=$(az ad sp list --display-name jmeteraksadmin -o tsv |awk '{print $5}')
    if az ad sp delete --id "$servicePrincipalId" 1>/dev/null; then
        echo "Service Principal deleted...."
    else
        echo "Failed to delete service Principal with ID [ $servicePrincipalId ].  Please delete manually"
        exit 1
    fi
}

fwk_install(){
#create the required service principal to use with AKS / ACR
# do this first to prevent acr creation if sp is not correct...
spId=$(az ad sp list --display-name $spname -o tsv --query [].appId)
if [[ -z ${spId}  ]]; then
    echo "Service Principal does not exist...."
    echo "Creating Service Principal..."
    sp=$(az ad sp create-for-rbac -n $spname -o tsv)
    if [ $? -ne 0 ]
        then
            echo "Failed to create service principal, error: '${?}'"
            exit 1
    fi
else
    echo "Service Principal - $spname already exists...."
    echo "please choose altenative name"
    exit 1
fi

servicePrincipal=$(echo $sp |awk -F\" '{print $1}')
clientSecret=$(echo $sp |awk -F\" '{print $4}')

if [[ -z ${servicePrincipal}  ]] || [[ -z ${clientSecret}  ]] ;
then
    echo "Service Principal credentials have not been retrieved ...."
    exit 1
else
    echo "Service Principal credentials have been created....."
fi

##create acr to use to store containers
if ! az acr show --name $acrName &>/dev/null; then
    echo "Container registry [ $acrName ] does not exist...."
    echo "Creating container registry..."
    az acr create --name $acrName --resource-group $resourceGroup --sku Basic --admin-enabled true
    if [ $? -ne 0 ]
        then
            echo "Failed to create container registry in the resource group [ $resourceGroup ] error: '${?}'"
            exit 1
    fi
else
    echo "Container registry [ $acrName ] already exists...."
fi

##build and push the master,slave and reporter images to acr


if ! az acr repository show -n testframeworkacr --image testframework/jmetermaster:latest &>/dev/null; then
    echo "master image does not exist....creating..."
    echo "building jmeter master container and pushing to [ $acrName ] in resource group [ $resourceGroup ]"
    az acr build -t testframework/jmetermaster:latest -f ../master/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "Failed to build and push master container error: '${?}'"
        exit 1
    else
        echo "jmeter master container completed...."
    fi
else
    echo "jmetermaster:lastest already existing in acr...."
fi

if ! az acr repository show -n testframeworkacr --image testframework/jmeterslave:latest &>/dev/null; then
    echo "slave image does not exist....creating..."
    echo "building jmeter slave container and pushing to [ $acrName ] in resource group [ $resourceGroup ]"
    az acr build -t testframework/jmeterslave:latest -f ../slave/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "Failed to build and push slave error: '${?}'"
        exit 1
    else
        echo "jmeter slave container completed...."
    fi
else
    echo "jmeterslave:lastest already existing in acr...."
fi

if ! az acr repository show -n testframeworkacr --image testframework/reporter:latest &>/dev/null; then
    echo "slave image does not exist....creating..."
    echo "building jmeter reporter container and pushing to [ $acrName ] in resource group [ $resourceGroup ]"
    az acr build -t testframework/reporter:latest -f ../reporter/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "Failed to build and push slave error: '${?}'"
        exit 1
    else
        echo "jmeter reporter container completed...."
    fi
else
    echo "reporter:lastest already existing in acr...."
fi


##create default AKS cluster with node size Standard_D2s_V3
echo "Creating AKS cluster with D2s_v3 nodes...."
az aks create \
    --resource-group $resourceGroup \
    --name jmeteraks \
    --node-count 3 \
    --service-principal $servicePrincipal \
    --client-secret $clientSecret \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 50 \
    --generate-ssh-keys \
	--disable-rbac \
	--node-vm-size Standard_D2s_v3 \
	--location $location

if [ $? -ne 0 ]
    then
        echo "Failed to create aks cluster, error: '${?}'"
        clean_up
fi


###get creds
az aks get-credentials --resource-group $resourceGroup --name jmeteraks --overwrite-existing

nodes=$(kubectl get nodes |awk '/aks-nodepool/ {print $1}')
if [ -z {$nodes} ]; then
    echo "issue with kubectl setup"
    exit 1
else
    echo "kubectl available...."
fi


#add reporter nodepool
az aks nodepool add --cluster-name jmeteraks -g $resourceGroup --name reporterpool --node-count 1 --node-vm-size Standard_D8s_v3
reporternode=$(kubectl get nodes |awk '/aks-reporterpool/ {print $1}')
kubectl taint nodes $reporternode sku=reporter:NoSchedule


echo "Creating Reporting...."
kubectl apply -f ../deploy/azure-premium.yaml
kubectl apply -f ../deploy/influxdb_svc.yaml
kubectl apply -f ../deploy/jmeter_influx_configmap.yaml
kubectl apply -f ../deploy/reporter.yaml

echo "Creating Jmeter Slaves.."
kubectl apply -f ../deploy/jslaves_svc.yaml
kubectl apply -f ../deploy/jmeter_slave.yaml

echo "Creating Jmeter Master"
kubectl apply -f ../deploy/jmeter-master-configmap.yaml
kubectl apply -f ../deploy/jmaster.yaml

echo "kubernetes deployment completed successfully"


influxdb_pod=$(kubectl get pods | grep report | awk '{print $1}')
kubectl exec -ti $influxdb_pod -- influx -execute 'CREATE DATABASE jmeter'

kubectl exec -ti $influxdb_pod -- curl 'http://admin:admin@127.0.0.1:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"jmeterdb","type":"influxdb","url":"http://localhost:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}'


}

###################
## functions end ##
###################

#####################################################################################
#Script execution starts here
#####################################################################################

resourceGroup=""  # Default to empty package
location=""  # Default to empty target

command=$1
case "$command" in
  # Parse options to the install sub command
  install )
    # Process package options
    shift
        while getopts hg:l:s: opt; do
                case ${opt} in
                    (h)
                        display_help
                        ;;
                    (g)
                        resourceGroup=$OPTARG
                        ;;
                    (l)
                        location=$OPTARG
                        ;;
                    (s)
                        spname=$OPTARG
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
    shift $((OPTIND -1))

    if [[ -z ${resourceGroup}  ]] || [[ -z ${location}  ]] || [[ -z ${spname}  ]] ;
        then
            echo "Resource Group,location and spname must be provided"
            exit 1
        else
            echo "the resource group will be:" $resourceGroup
            echo "the location of the deployment will be:" $location
            echo "spname will be...." $spname
    fi

    #check for resource group and create if not existing
    rg_check
    #create sp and AKS cluster
    fwk_install
    echo "install completed successfully...."
    exit 0
    ;;

    delete )
        echo "this will remove the deployment....."
        read -p "Are you sure? " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]];
        then
            shift
            while getopts hg:s: opt; do
                case ${opt} in
                    (h)
                        display_help
                        ;;
                    (g)
                        resourceGroup=$OPTARG
                        ;;
                    (s)
                        spname=$OPTARG
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
            shift $((OPTIND -1))

            if [[ -z ${resourceGroup}  ]] || [[ -z ${spname}  ]];
            then
                echo "Resource Group and spname must be provided"
                exit 1
            else
                echo "the resource group to delete will be: " $resourceGroup
                echo "spname to be deleted is: "$spname
                echo ""
            fi
        echo "deleting !"
        clean_up
        else
            echo "no action has been taken......"
        fi

        echo ""
        echo "resources successfull deleted...."
        exit 0
        ;;

    validate )
        echo "This option will validate your subscription / environment to support the installation of the test framework..."
            # Process package options
        shift
        while getopts hg:l:s: opt; do
                case ${opt} in
                    (h)
                        display_help
                        ;;
                    (g)
                        resourceGroup=$OPTARG
                        ;;
                    (l)
                        location=$OPTARG
                        ;;
                    (s)
                        spname=$OPTARG
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
    shift $((OPTIND -1))

    if [[ -z ${resourceGroup}  ]] || [[ -z ${location}  ]] || [[ -z ${spname}  ]] ;
        then
            echo "Resource Group,location and spname must be provided"
            exit 1
        else
            echo "the resource group will be:" $resourceGroup
            echo "the location of the deployment will be:" $location
            echo "spname will be...." $spname
    fi
    #check resource group
    rg_check
    # check kubectl is available
    kube_check
    #check AKS cluster
    cluster_check
    #spname check
    sp_check
    exit 0
    ;;

    * ) 
        display_help
    ;;
esac




