#!/usr/bin/env bash
#Script writtent to stop a running jmeter master test
#Kindly ensure you have the necessary kubeconfig

working_dir=`pwd`

#Get namesapce variable

master_pod=`kubectl get pods | grep jmeter-master | awk '{print $1}'`

kubectl exec -ti $master_pod bash /jmeter/apache-jmeter-5.2.1/bin/stoptest.sh
