FROM ubuntu:18.04
		
RUN		apt-get -y update && apt-get -y upgrade		
RUN 	apt-get -y install wget gnupg curl

RUN apt-get update && \
apt-get install -y influxdb && \
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - && \
#add-apt-repository "deb https://packages.grafana.com/oss/deb stable main" && \
echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list &&\
apt-get  update && \
apt-get install grafana -y && \
update-rc.d grafana-server defaults && \
apt-get install influxdb-client -y


# Grafana
EXPOSE	3000

# InfluxDB Admin server
EXPOSE	8083

# InfluxDB HTTP API
EXPOSE	8086

# InfluxDB HTTPS API
EXPOSE	8084

# -------- #
#   Run!   #
# -------- #

ENTRYPOINT service influxdb start && service grafana-server start
