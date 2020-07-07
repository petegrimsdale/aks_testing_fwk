#!/bin/bash
#------------------------------------------------------------------
# Script to deploy AKS based Jmeter test framework
# 
# Authors: Pete Grimsdale
#------------------------------------------------------------------

# Variables

# SubscriptionId of the current subscription
subscriptionId=$(az account show --query id --output tsv)
logfile=./testfwklog
exec > >(tee -ai $logfile) 2>&1

rgcreate=false
dt=$(date)
echo "### Logging Info ###"
echo "INFO: Starting installation action at:"$dt
############################################################################
#common functions
############################################################################

#script version and date
get_version(){

    #echo "Installer version 1.1"
    #echo "Version Date: 29/01/2020"
    #echo "INFO:Installer version 1.2"
    #echo "INFO:Version Date: 30/01/2020"
    #echo "INFO:Installer version 1.3"
    #echo "INFO:Version Date: 6/02/2020"
    #echo "INFO:Installer version 1.4"
    #echo "INFO:Version Date: 20/02/2020"
    #echo "INFO:Installer version 1.5"
    #echo "INFO:Version Date: 08/03/2020"
    echo "INFO:Installer version 1.6"
    echo "INFO:Version Date: 22/06/2020"
}

# Check if the resource group already exists
rg_check() {
    rg=$resourceGroup

    echo "Checking if [ $resourceGroup ] resource group actually exists in the [$subscriptionId] subscription..."
    if [ $command == "install" ]; then
        if ! az group show --name "$resourceGroup" &>/dev/null; then
            echo "INFO:No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
            echo "INFO:Creating [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription..."
            rgcreate=true

            # Create the resource group
            if az group create --name "$resourceGroup" --location "$location" 1>/dev/null; then
                echo "INFO:[ $resourceGroup ] resource group successfully created in the [ $subscriptionId ] subscription"
            else
                echo "ERROR:Failed to create [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription"
                exit 1
            fi
        else
            echo "INFO:[ $resourceGroup ] resource group already exists in the [ $subscriptionId ] subscription"
            rgcreate=false
        fi

        #check fwkrg
        if [[ ! -z ${fwkrg} ]]; then
            if ! az group show --name "$fwkrg" &>/dev/null; then
                echo "INFO:No [ $fwkrg ] resource group actually exists in the [ $subscriptionId ] subscription"
                echo "INFO:Creating [ $fwkrg ] resource group in the [ $subscriptionId ] subscription..."

            # Create the resource group
                if az group create --name "$fwkrg" --location "$location" 1>/dev/null; then
                    echo "INFO:[ $fwkrg ] resource group successfully created in the [ $subscriptionId ] subscription"
                else
                    echo "ERROR:Failed to create [ $fwkrg ] resource group in the [ $subscriptionId ] subscription"
                    exit 1
                fi
            else
                echo "INFO:[ $fwkrg ] resource group already exists in the [ $subscriptionId ] subscription"
            fi
        fi

    else
        if ! az group show --name "$resourceGroup" &>/dev/null; then
            echo "INFO:No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
        else
            echo "INFO:[ $resourceGroup ] resource group already exists in the [ $subscriptionId ] subscription"
        fi
    fi

    

}


# Display usage information and exit
display_help() {
    echo "Usage: $0 [option...]" >&2
    echo
    echo "   command    install / validate"
    echo "   Full Testing framework install - creates rg, ACR, AKS cluster and deployment"
    echo "   -g		        Resource Group Name."
    echo "   -l		        Location."
    echo "   -s		        spname"
    echo "   --vnetname		vnet name (optional install only)"
    echo "   --subnetname	subnet name (optional install only)"
    echo "   --fwkrg        resource group to install test fwk into (optional install only with vnet)"
    echo "   -v		        vnet address prefix (optional install only)"
    echo "   -n		        subnet address prefix (optional install only)"
    echo
    echo "   command    delete"
    echo "   -g		Resource Group Name."
    echo "   -s		spname"
    echo "   --fwkrg provide the test fwk resource group to delete"
    echo 
    echo "   command    kube_deploy"
    echo "   deploys only the Kubernetes elements to the existing fwk cluster"
    echo "   -g		Resource Group Name."
    echo "   -c		clustername"
    exit 1
}

#sp check
sp_check() {
spId=$(az ad sp list --display-name $spname -o tsv --query [].appId)
if [[ -z ${spId}  ]]; then
    echo "INFO:Service Principal - $spname a does not exist...."
else
    echo "INFO:Service Principal - $spname already exists...."
    echo "INFO:Please choose altenative name"
fi
}

# kubectl check
kube_check() {
    echo "INFO:Checking if kubectl is present"

    if ! hash kubectl 2>/dev/null
        then
            echo "INFO:'kubectl' was not found...."
            echo "INFO:Kindly ensure that you can acces an existing kubernetes cluster via kubectl / install kubectl"
    else
        echo "INFO: 'kubectl' was successfully found..."
    fi
}

#check AKS cluster
cluster_check() {
    echo "INFO:checking access to AKS cluster...."
    aksCluster=$(az aks list -g $resourceGroup -o tsv --query [].name)
    if [[ -z ${aksCluster}  ]]; then
        echo "INFO:No AKS cluster exists in the resource group [ $resourceGroup ]...."
    else
        echo "INFO:An existing AKS cluster, $aksCluster exists in [ $resourceGroup ]..."
    fi
}

# Clean up on script failure
# remove resource group and SP
clean_up() {

    #remove resource group
    if ! az group show --name "$resourceGroup" &>/dev/null; then
        echo "ERROR:No [ $resourceGroup ] resource group actually exists in the [ $subscriptionId ] subscription"
        echo ""
        exit 1
    else
        echo "INFO: deleting resource group..."
        if [ ! -z $fwkrg ];then
            if az group delete --name "$fwkrg" -y --no-wait  1>/dev/null; then
                echo "INFO:[ $fwkrg ] will be deleted from the [ $subscriptionId ] subscription. Please check for full removal"
            else
                echo "ERROR: Failed to delete [ $fwkrg ] resource group in the [ $subscriptionId ] subscription.  Please delete manually"
                exit 1
            fi
        else
            if [ $rgcreate == 'true' ];then
                if az group delete --name "$resourceGroup" -y --no-wait  1>/dev/null; then
                    echo "INFO:[ $resourceGroup ] will be deleted from the [ $subscriptionId ] subscription. Please check for full removal"
                else
                    echo "ERROR: Failed to delete [ $resourceGroup ] resource group in the [ $subscriptionId ] subscription.  Please delete manually"
                    exit 1
                fi
            fi
        fi
    fi

#remove the SP
    #get the sp id
    echo "INFO:retrieving Service Principal Id for $spname"
    servicePrincipalId=$(az ad sp list --display-name $spname -o tsv --query [].appId)
    echo "INFO: Service Principal ID is:"$servicePrincipalId
    if az ad sp delete --id "$servicePrincipalId" 1>/dev/null; then
        echo "INFO: Service Principal deleted...."
    else
        echo "ERROR: Failed to delete service Principal with name $spname and ID [ $servicePrincipalId ].  Please delete manually"
        exit 1
    fi

#remove the updated template files
if [ -f ../deploy/jslave.yaml ]; then
rm -f ../deploy/jslave.yaml
fi

if [ -f ../deploy/jmaster.yaml ]; then
rm -f ../deploy/jmaster.yaml
fi

if [ -f ../deploy/reporter.yaml ]; then
rm -f ../deploy/reporter.yaml
fi


}

kube_install(){

###get creds
if [ ! -z $fwkrg ];then
    if az aks get-credentials --resource-group $fwkrg --name $aksName --overwrite-existing &>/dev/null; then
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
else
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
fi

#check ACR is available
if [[ -z $acrName ]];then
acrsuffix=$(echo $aksName|awk -F"-" '{print $2}')
    if [[ -z $acrsuffix ]];then
        echo "ERROR: ACR name cannot be empty"
        exit 1
    else
        acrName="testframeworkacr"$acrsuffix
        echo "INFO:ACR name is "$acrName
    fi
else
    echo "INFO:ACR name is "$acrName
fi



acrCheck=$(az acr check-name --name $acrName -o tsv --query nameAvailable)
if [ $acrCheck == "true" ]; then
    echo "ERROR:Container registry [ $acrName ] does not exist...."
    exit 1
else
    echo "INFO:Container registry [ $acrName ] exists...."
fi

#add reporter nodepool
#check if already exists

reportingnodepool=0
if [ ! -z $fwkrg ];then
    for i in $(az aks nodepool list -g $fwkrg --cluster-name $aksName -o tsv --query [].name)
    do
        if [ $i == "reporterpool" ]; then
            echo "INFO: Reporting Node Pool aready exists"
            reportingnodepool=1
        fi
    done

    if [[ $reportingnodepool -eq 0 ]]; then
        echo "INFO:Adding reporting nodepool..."
        az aks nodepool add --cluster-name $aksName -g $fwkrg --name reporterpool --node-count 1 --node-vm-size Standard_D8s_v3
        reporternode=$(kubectl get nodes |awk '/aks-reporterpool/ {print $1}')
        echo "INFO: Tainting reporting node..."
        kubectl taint nodes $reporternode sku=reporter:NoSchedule
        echo "INFO: Tainting reporting node completed..."
    fi
else
    for i in $(az aks nodepool list -g $resourceGroup --cluster-name $aksName -o tsv --query [].name)
    do
        if [ $i == "reporterpool" ]; then
            echo "INFO: Reporting Node Pool aready exists"
            reportingnodepool=1
        fi
    done

    if [[ $reportingnodepool -eq 0 ]]; then
        echo "INFO:Adding reporting nodepool..."
        az aks nodepool add --cluster-name $aksName -g $resourceGroup --name reporterpool --node-count 1 --node-vm-size Standard_D8s_v3
        reporternode=$(kubectl get nodes |awk '/aks-reporterpool/ {print $1}')
        echo "INFO: Tainting reporting node..."
        kubectl taint nodes $reporternode sku=reporter:NoSchedule
        echo "INFO: Tainting reporting node completed..."
    fi
fi
echo "INFO:Generating yaml files from templates..."

# read the yaml template from a file and substitute the string 
# ###acrname### with the value of the acrName variable
sed "s/###acrname###/$acrName/g" ../deploy/reporter.yaml.template > ../deploy/reporter.yaml
sed "s/###acrname###/$acrName/g" ../deploy/jslave.yaml.template > ../deploy/jslave.yaml
sed "s/###acrname###/$acrName/g" ../deploy/jmaster.yaml.template > ../deploy/jmaster.yaml

echo "INFO:Template yaml files generated in deploy directory..."

# apply the yaml with the substituted value

echo "INFO:Creating Reporting deployment...."
kubectl apply -f ../deploy/azure-premium.yaml
kubectl apply -f ../deploy/influxdb_svc.yaml
kubectl apply -f ../deploy/jmeter_influx_configmap.yaml
kubectl apply -f ../deploy/reporter.yaml
echo "INFO:Reporting deployment complete...."
echo "INFO:Creating Jmeter Slaves.."
kubectl apply -f ../deploy/jslaves_svc.yaml
kubectl apply -f ../deploy/jslave.yaml
echo "INFO:Jmeter slave deployment complete...."

echo "INFO:Creating Jmeter Master"
kubectl apply -f ../deploy/jmeter-master-configmap.yaml
kubectl apply -f ../deploy/jmaster.yaml
echo "INFO: Jmeter Master deployment complete...."

influxdb_pod=$(kubectl get pods | grep report | awk '{print $1}')
echo "INFO: Waiting for reporting container to start...."

COUNTER=1
while [ `kubectl get pods |grep report |awk '{print $3}'` != "Running" ]
do
echo "INFO: Checking reporting pod is running ...check#"$COUNTER
let COUNTER++
sleep 5
done

echo "INFO: reporting container started...."
echo "INFO: Adding jmeter database to Influxdb...."

kubectl exec -ti $influxdb_pod -- influx -execute 'CREATE DATABASE jmeter'

echo "INFO: Jmeter database added to Influxdb...."
echo "INFO: Adding default datasource to grafana...."
#give Grafana time to start
# changed to remove sleep and replace with kubectl action
#sleep 20
#kubectl exec -ti $influxdb_pod -- curl 'http://admin:admin@localhost:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"jmeterdb","type":"influxdb","url":"http://localhost:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}'

kubectl cp ../deploy/datasource.json $influxdb_pod:/datasource.json
kubectl exec -ti $influxdb_pod -- /bin/bash -c 'until [[ $(curl "http://admin:admin@localhost:3000/api/datasources" -X POST -H "Content-Type: application/json;charset=UTF-8" --data-binary @datasource.json) ]]; do sleep 5; done'

echo "INFO: Default datasource added to grafana...."


echo "INFO: Adding default dashboard"
kubectl cp ../deploy/jmeterDash.json $influxdb_pod:/jmeterDash.json

kubectl exec -ti $influxdb_pod -- curl 'http://admin:admin@localhost:3000/api/dashboards/db' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '@jmeterDash.json'

echo "INFO: Default dashboard has been added"

echo "INFO: kubernetes details..."
kubectl get -n default all


lbIp=$(kubectl get svc |grep reporter |awk '{print $4}')

echo "#########################################"
echo "## Grafana can be accessed at: "$lbIp" ##"
echo "#########################################"
echo "## AKS cluster name is: "$aksName"     ##"
echo "#########################################"


}


vnet_check(){
    #check to see whether vnet exists or needs to be created
    #assumes resource group creation means no vnet

    if [ $rgcreate == "false" ]; then
        echo "INFO: resource group exists - check for existing Vnet"
        VNET_ID=$(az network vnet show --resource-group $resourceGroup --name $vnetName --query id -o tsv)
        echo "vnetid"$VNET_ID
        if [[ -z ${VNET_ID}  ]]; then
            echo "INFO: VNET does not exist, Vnet will be created"
            #create vnet
            if az network vnet create --resource-group $resourceGroup \
                                     --name $vnetName \
                                     --address-prefixes $vnetprefix \
                                     --subnet-name $subnetName \
                                     --subnet-prefix $subnetprefix \
                                     1>/dev/null; then
                echo "INFO: VNET successfully created"
                VNET_ID=$(az network vnet show --resource-group $resourceGroup --name $vnetName --query id -o tsv)
                SUBNET_ID=$(az network vnet subnet show --resource-group $resourceGroup --vnet-name $vnetName --name $subnetName --query id -o tsv)
            else
                echo "ERROR: Failed to created Vnet with supplied parameters"
                exit 1
            fi
        else
            echo "INFO:  VNET already exists - re-use this vnet"
            SUBNET_ID=$(az network vnet subnet show --resource-group $resourceGroup --vnet-name $vnetName --name $subnetName --query id -o tsv)
            if [[ -z ${SUBNET_ID} ]]; then
                echo "INFO: Subnet $subnetName not found...adding"
                if az network vnet subnet create --address-prefixes $subnetprefix --name $subnetName --resource-group $resourceGroup --vnet-name $vnetName 1>/dev/null; then
                    echo "INFO: subent $subnetName created successfully"
                    SUBNET_ID=$(az network vnet subnet show --resource-group $resourceGroup --vnet-name $vnetName --name $subnetName --query id -o tsv)
                else
                echo "ERROR: Subnet could not be created"
                exit 1
                fi
            fi
        fi
    else
        echo "INFO: Creating required Vnet and Subnet"
        if az network vnet create --resource-group $resourceGroup \
                                     --name $vnetName \
                                     --address-prefixes $vnetprefix \
                                     --subnet-name $subnetName \
                                     --subnet-prefix $subnetprefix \
                                     1>/dev/null; then
                echo "INFO: VNET successfully created"
                VNET_ID=$(az network vnet show --resource-group $resourceGroup --name $vnetName --query id -o tsv)
                SUBNET_ID=$(az network vnet subnet show --resource-group $resourceGroup --vnet-name $vnetName --name $subnetName --query id -o tsv)
        else
                echo "ERROR: Failed to created Vnet with supplied parameters"
                exit 1
        fi
    fi
    echo "INFO: Vnet Id is "$VNET_ID
    echo "INFO: Subnet Id is "$SUBNET_ID


}

fwk_install(){

#default settings
#ACR Name to be used
#fix unique naming
str=$(uuidgen)
if [ ! -z $str ]; then
    suffix=$(echo "${str: -5}")
else
    str=$(date +'%s')
    suffix=$(echo "${str: -5}")
fi
if [ -z $suffix ];then
    echo "ERROR: suffix error"
    exit 1
fi

echo "INFO: suffix used is: "$suffix
#suffix=$(echo $RANDOM % 1000 + 1 |bc)
acrbase="testframeworkacr"
acrName=$acrbase$suffix
#AKS cluster name
aksbase="jmeteraks-"
aksName=$aksbase$suffix


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

servicePrincipal=$(echo $sp |awk '{print $1}')
clientSecret=$(echo $sp |awk '{print $4}')

if [[ -z ${servicePrincipal}  ]] || [[ -z ${clientSecret}  ]] ;
then
    echo "ERROR: Service Principal credentials have not been retrieved exiting...."
    exit 1
else
    echo "INFO:Service Principal credentials have been created....."
fi


##create acr to use to store containers
if [[ ! -z ${fwkrg} ]]; then
        echo "Info - Using supplied fwk resource group name"
        acrCheck=$(az acr check-name --name $acrName -o tsv --query nameAvailable)
        if [ $acrCheck == "true" ]; then
            echo "INFO:Container registry [ $acrName ] does not exist...."
            echo "INFO:Creating container registry..."
            echo "DEBUG: az acr create --name "$acrName" --resource-group "$fwkrg" --sku Basic --admin-enabled true"
            az acr create --name $acrName --resource-group $fwkrg --sku Basic --admin-enabled true
            if [ $? -ne 0 ]
                then
                    echo "ERROR: Failed to create container registry in the resource group [ $fwkrg ] "
                    exit 1
                else
                    echo "INFO: Acr $acrName created"
            fi
        else
            echo "Container registry [ $acrName ] already exists...."
            exit 1
        fi
else
acrCheck=$(az acr check-name --name $acrName -o tsv --query nameAvailable)
if [ $acrCheck == "true" ]; then
    echo "INFO:Container registry [ $acrName ] does not exist...."
    echo "INFO:Creating container registry..."
    echo "DEBUG: az acr create --name "$acrName" --resource-group "$resourceGroup" --sku Basic --admin-enabled true"
    az acr create --name $acrName --resource-group $resourceGroup --sku Basic --admin-enabled true
    if [ $? -ne 0 ]
        then
            echo "ERROR: Failed to create container registry in the resource group [ $resourceGroup ] "
            exit 1
        else
            echo "INFO: Acr $acrName created"
    fi
else
    echo "Container registry [ $acrName ] already exists...."
    exit 1
fi
fi



##build and push the master,slave and reporter images to acr


if ! az acr repository show -n $acrName --image testframework/jmetermaster:latest &>/dev/null; then
    echo "INFO:master image does not exist....creating..."
    echo "INFO:building jmeter master container and pushing to [ $acrName ] "
    az acr build -t testframework/jmetermaster:latest -f ../master/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "ERROR:Failed to build and push master container error: '${?}'"
        exit 1
    else
        echo "INFO:jmeter master container completed...."
    fi
else
    echo "INFO:jmetermaster:lastest already existing in acr...."
fi

if ! az acr repository show -n $acrName --image testframework/jmeterslave:latest &>/dev/null; then
    echo "INFO:slave image does not exist....creating..."
    echo "INFO:building jmeter slave container and pushing to [ $acrName ]"
    az acr build -t testframework/jmeterslave:latest -f ../slave/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "ERROR:Failed to build and push slave error: '${?}'"
        exit 1
    else
        echo "INFO:jmeter slave container completed...."
    fi
else
    echo "INFO:jmeterslave:lastest already existing in acr...."
fi

if ! az acr repository show -n $acrName --image testframework/reporter:latest &>/dev/null; then
    echo "INFO:slave image does not exist....creating..."
    echo "INFO:building jmeter reporter container and pushing to [ $acrName ]"
    az acr build -t testframework/reporter:latest -f ../reporter/Dockerfile -r $acrName .
    if [ $? -ne 0 ]
    then
        echo "ERROR:Failed to build and push slave error: '${?}'"
        exit 1
    else
        echo "INFO:jmeter reporter container completed...."
    fi
else
    echo "INFO:reporter:lastest already existing in acr...."
fi

if [ ! -z ${vnetName} ]; then
    ## assign role to SP
    az role assignment create --assignee $servicePrincipal --scope $VNET_ID --role Contributor
    ##create vnet and subnet if required for deployment
    echo "INFO: Creating AKS cluster with Vnet deployment"
    ##create default AKS cluster with node size Standard_D2s_V3
    echo "INFO:Creating AKS cluster $aksName with D2s_v3 nodes...."
    if [ ! -z ${fwkrg} ]; then
        az aks create \
                --resource-group $fwkrg \
                --name $aksName \
                --node-count 3 \
                --service-principal $servicePrincipal \
                --client-secret $clientSecret \
                --enable-cluster-autoscaler \
                --min-count 1 \
                --max-count 50 \
                --generate-ssh-keys \
                --disable-rbac \
                --node-vm-size Standard_D2s_v3 \
                --location $location \
                --vnet-subnet-id $SUBNET_ID

        if [ $? -ne 0 ]
        then
            echo "ERROR: Failed to create aks cluster, error: '${?}'"
            clean_up
        fi
    else
        az aks create \
                --resource-group $resourceGroup \
                --name $aksName \
                --node-count 3 \
                --service-principal $servicePrincipal \
                --client-secret $clientSecret \
                --enable-cluster-autoscaler \
                --min-count 1 \
                --max-count 50 \
                --generate-ssh-keys \
                --disable-rbac \
                --node-vm-size Standard_D2s_v3 \
                --location $location \
                --vnet-subnet-id $SUBNET_ID

        if [ $? -ne 0 ]
        then
            echo "ERROR: Failed to create aks cluster, error: '${?}'"
            clean_up
        fi
    fi
else
    echo "INFO: Framework Deployment will be without a Vnet"
    ##create default AKS cluster with node size Standard_D2s_V3
    echo "INFO:Creating AKS cluster $aksName with D2s_v3 nodes...."
    az aks create \
        --resource-group $resourceGroup \
        --name $aksName \
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
            echo "ERROR: Failed to create aks cluster, error: '${?}'"
            clean_up
    fi
fi

# call the kubernetes install function to deploy kube components
kube_install

}

####################
## functions end ##
####################

#####################################################################################
#Script execution starts here
#####################################################################################
resourceGroup=""  # Default to empty package
location=""  # Default to empty target


get_version

command=$1
case "$command" in
  # Parse options to the install sub command
install )
    # Process package options
    shift
        while getopts hg:l:s:v:n:-: opt; do
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
                    (v)
                        vnetprefix=$OPTARG
                        ;;
                    (n)
                        subnetprefix=$OPTARG
                        ;;
                    (-)
						case "${OPTARG}" in
                			vnetname)
                    			vnetName="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    			;;
                			subnetname)
                    			subnetName="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    			;;
                            fwkrg)
                    			fwkrg="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    			;;
							*)
								echo "-- option not supported"
                                display_help
							;;
						esac
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

    if [[ -z ${resourceGroup}  ]] || [[ -z ${location}  ]] || [[ -z ${spname}  ]] ;then
        echo "ERROR:Resource Group,location and spname must be provided"
        exit 1
    else
        if [[ ! -z ${vnetName} ]]; then
            if [[ -z ${subnetName} ]]; then
                echo "ERROR:  subnet name must be provided when VnetName is provided"
                exit 1
            else
                if [[ ! -z ${vnetprefix} ]]; then
                    if [[ -z ${subnetprefix} ]]; then
                        echo "ERROR:  subnet prefix must be provided when vnet prefix is provided"
                        exit 1
                    else
                        dt=$(date +"%d/%m %T")
                        echo $dt" INFO: Starting Framework deployment ..."
                        echo "INFO: Vnet deployment will be used"
                        echo "INFO: The resource group will be:" $resourceGroup 
                        echo "INFO: The location of the deployment will be:" $location
                        echo "INFO: The Service Principal name used will be...." $spname
                        echo "INFO: VnetName will be "$vnetName
                        echo "INFO: subnetName will be "$subnetName
                        echo "INFO: Vnet prefix will be "$vnetprefix
                        echo "INFO: Subnet prefix will be "$subnetprefix

                    fi
                else
                        dt=$(date +"%d/%m %T")
                        echo $dt" INFO: Starting Framework deployment ..."
                        echo "INFO: Non Vnet deployment will be used"
                        echo "INFO: The resource group will be:" $resourceGroup 
                        echo "INFO: The location of the deployment will be:" $location
                        echo "INFO: The Service Principal name used will be...." $spname
                        echo "INFO: VnetName will be "$vnetName
                        echo "INFO: subnetName will be "$subnetName  
                fi               
            fi
        else
            dt=$(date +"%d/%m %T")
            echo $dt" INFO: Starting Framework deployment ..."
            echo "INFO: Non Vnet deployment will be used"
            echo "INFO: The resource group will be:" $resourceGroup 
            echo "INFO: The location of the deployment will be:" $location
            echo "INFO: The Service Principal name used will be...." $spname
        fi
    fi

    #check for resource group and create if not existing
    rg_check
    #check vnet setup/requrirement if provided
    if [ $vnetName ]; then
        echo "INFO: Vnet setup"
        vnet_check
    fi
    #create sp and AKS cluster
    fwk_install
    dt=$(date +"%d/%m %T")
    echo $dt" INFO: Framework install completed successfully...."
    exit 0
;;

kube_deploy )
    # Process package options
    shift
        while getopts hg:c: opt; do
                case ${opt} in
                    (h)
                        display_help
                        ;;
                    (g)
                        resourceGroup=$OPTARG
                        ;;
                    (c)
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
    shift $((OPTIND -1))

    if [[ -z ${resourceGroup}  ]] || [[ -z ${aksName}  ]] ;
        then
            echo "Resource Group and AKS cluster name must be provided"
            exit 1
        else
            dt=$(date +"%d/%m %T")
            echo $dt" INFO: Starting Kube deployment ..."
            echo "INFO:the resource group will be:" $resourceGroup
            echo "INFO:AKS name assumed will be: " $aksName
    fi

    #check for resource group and create if not existing
    rg_check
    #install Kubernetes elements
    kube_install
    dt=$(date +"%d/%m %T")
    echo $dt" INFO: Kubernetes only deployment completed successfully...."
    exit 0
;;

delete )
        echo "this will remove the deployment....."
        read -p "Are you sure? (press "y" for yes)" -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]];
        then
            shift
            while getopts hg:s:-: opt; do
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
                    (-)
						case "${OPTARG}" in
                            fwkrg)
                    			fwkrg="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    			;;
							*)
								echo "-- option not supported"
                                display_help
							;;
						esac
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
                if [ ! -z $fwkrg ];then
                    echo "the resource group to delete will be: " $fwkrg
                    echo "spname to be deleted is: "$spname
                    echo ""
                else
                    rgcreate=true
                    echo "the resource group to delete will be: " $resourceGroup
                    echo "spname to be deleted is: "$spname
                    echo ""
                fi
            fi
        echo "deleting !"
        clean_up
        else
            echo "no action has been taken......"
        fi
        dt=$(date +"%d/%m %T")
        echo $dt" INFO: Framework deployment completed successfully...."
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




