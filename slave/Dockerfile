# Version 2.0
# Added plugin support
FROM openjdk:8-jdk-slim
		
ARG JMETER_VERSION=5.2.1
		
RUN apt-get clean && \
apt-get update && \
apt-get -qy install \
wget \
unzip \
curl


ENV JMETER_HOME /jmeter/apache-jmeter-$JMETER_VERSION/
ENV JMETER_PLUGINS_MANAGER_VERSION 1.4
ENV CMDRUNNER_VERSION 2.2
ENV PATH $JMETER_HOME/bin:$PATH
ENV AZURE_PLUGIN_VERSION 0.2.3

RUN  mkdir /jmeter \
&& cd /jmeter/ \
&& wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-$JMETER_VERSION.tgz \
&& tar -xzf apache-jmeter-$JMETER_VERSION.tgz \
&& rm apache-jmeter-$JMETER_VERSION.tgz\
&& curl --location --output ${JMETER_HOME}/lib/ext/jmeter-plugins-manager-${JMETER_PLUGINS_MANAGER_VERSION}.jar http://search.maven.org/remotecontent?filepath=kg/apc/jmeter-plugins-manager/${JMETER_PLUGINS_MANAGER_VERSION}/jmeter-plugins-manager-${JMETER_PLUGINS_MANAGER_VERSION}.jar \
&& curl --location --output ${JMETER_HOME}/lib/cmdrunner-${CMDRUNNER_VERSION}.jar http://search.maven.org/remotecontent?filepath=kg/apc/cmdrunner/${CMDRUNNER_VERSION}/cmdrunner-${CMDRUNNER_VERSION}.jar \
&& java -cp ${JMETER_HOME}/lib/ext/jmeter-plugins-manager-${JMETER_PLUGINS_MANAGER_VERSION}.jar org.jmeterplugins.repository.PluginManagerCMDInstaller \
&& PluginsManagerCMD.sh install \
jmeter.backendlistener.azure=${AZURE_PLUGIN_VERSION} \
&& jmeter --version \
&& PluginsManagerCMD.sh status 

ADD VERSION ../installs/

ENTRYPOINT $JMETER_HOME/bin/jmeter-server \
-Dserver.rmi.localport=50000 \
-Dserver_port=1099 \
-Jserver.rmi.ssl.disable=true