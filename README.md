# AKS based scalable Jmeter Test Framework with Grafana

## Introduction
This Jmeter based testing framework provides a scalable test harness to support load testing of applications using Apache Jmeter based test scripts.  The framework excludes support for writing a Jmeter test plan but assumes a test plan in the form of a jmx files is available.  The testing framework utilizes a master Jmeter node with one or more slave nodes used to run the tests.  The deployment assumes a Jmeter backend listener is configured within the test plan to support writing metrics to the Influx database which can then be presented via a Grafana dashboard.  The initial deployment only deploys a single jmeter-slave pod but can be scaled as needed to support the required number of client threads.

## Architecture


## Deployment

### Installing

### Set up Jmeter Dashboard

### Running your first Jmeter test
