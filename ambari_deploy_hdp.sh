# Script to install HDP 2.5, Nifi 1.0, Zeppein with Truck demo and Nifi-Twitter demo. Run below command to kick off:  
# curl -sSL https://raw.githubusercontent.com/aengusrooneyhortonworks/HadoopClusterBuild/master/deploy_hdp.sh | sudo -E sh

#To run on multinode: run below on non-ambariserver nodes first
#export ambari_server=<FQDN of host running ambari-server>; export ambari_version=2.4.2.0; curl -sSL https://raw.githubusercontent.com/seanorama/ambari-bootstrap/master/ambari-bootstrap.sh | sudo -E sh ;


rm -rf ~/ambari-bootstrap
set -e -x
export hdp_ver=${hdp_ver:-2.5}                       #version of HDP
export host_count=${host_count:-ask}                 #num nodes in cluster (including Ambari)
export install_nifidemo="${install_nifidemo:-true}"  #whether to install nifi demo (works on hdp2.4/2.5) 
export install_iotdemo="${install_iotdemo:-true}"   #whether to install trucking demo (currently only works on HDP 2.4)
export install_nifisolr_on_all_nodes="${install_nifisolr_on_all_nodes:-true}"  #whether nifi/solr should be installed on all nodes
export ambari_services=${ambari_services:-HDFS HIVE PIG SPARK MAPREDUCE2 TEZ YARN ZOOKEEPER AMBARI_METRICS ATLAS}  #choose core services
export enable_llap="${enable_llap:-false}"
export cluster_name="${cluster_name:-hdp}"
export ambari_password=${ambari_password:-BadPass#1}     ##  For security purposes, when installing on AWS, this password will be overridden with your AWS accountid
#export public_ip=$(curl icanhazip.com)
#export nifi_flow=${nifi_flow:-https://gist.githubusercontent.com/abajwa-hw/3a3e2b2d9fb239043a38d204c94e609f/raw}    # nifi flow.xml to import

#service user for Ambari to setup demos
export service_user="demokitadmin"
export service_password="BadPass#1"

#only use ambari service to iotdemo on 2.4
#if ([ "${hdp_ver}" = "2.4" ] && [ "${install_iotdemo}" = true ]); then
#	export install_iot_service=true
#fi

#on 2.5, pick flow.xml with both iotdemo flow and twitter flow
if ([ "${hdp_ver}" = "2.5" ] && [ "${install_iotdemo}" = true ]); then
	export nifi_flow="https://gist.githubusercontent.com/abajwa-hw/a78634099c82cd2bab1ccceb8cc2b86e/raw"
else
	export nifi_flow="https://gist.githubusercontent.com/abajwa-hw/3a3e2b2d9fb239043a38d204c94e609f/raw"
fi


export install_ambari_server=true
export ambari_version=2.4.2.0

# java7 doesn't work with ambari 2.4.2 (at least on RHEL7)
#if [ "${hdp_ver}" = "2.4" ]; then
#	export java_version=7
#fi

#remove unneeded repos
if [ -f /etc/yum.repos.d/zfs.repo ]; then
  rm -f /etc/yum.repos.d/zfs.repo
fi

if [ -f /etc/yum.repos.d/lustre.repo ]; then
  rm -f /etc/yum.repos.d/lustre.repo
fi  


#install ambari-server/agent using bootstrap
yum install -y git
cd ~
sudo git clone https://github.com/seanorama/ambari-bootstrap.git
bash ~/ambari-bootstrap/ambari-bootstrap.sh

sleep 20

#create demokitadmin user
curl -iv -u admin:admin -H "X-Requested-By: blah" -X POST -d "{\"Users/user_name\":\"${service_user}\",\"Users/password\":\"${service_password}\",\"Users/active\":\"true\",\"Users/admin\":\"true\"}" http://localhost:8080/api/v1/users

#if running on AWS, fetch accountId
if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
  echo "AWS detected, reading accountId..."
  eval $(curl -sSL http://169.254.169.254/latest/dynamic/instance-identity/document \
    | awk -F\" '/:/ {print "export "$2"="$4}')

  #if accountId not empty, use it as password for admin user
  echo "Overriding ambari_password to AWS accountid..."
  if [ -n "${accountId}" ]; then
    export ambari_password=${accountId} 
  fi  

else
    echo "non-AWS detecting. Leaving pasword to default"
fi

#update admin password
curl -iv -u admin:admin -H "X-Requested-By: blah" -X PUT -d "{ \"Users\": { \"user_name\": \"admin\", \"old_password\": \"admin\", \"password\": \"${ambari_password}\" }}" http://localhost:8080/api/v1/users/admin



if [ "${hdp_ver}" = "2.5" ]; then
	sudo git clone -b hdp25 https://github.com/hortonworks-gallery/iotdemo-service.git   /var/lib/ambari-server/resources/stacks/HDP//${hdp_ver}/services/IOTDEMO25
else
	sudo git clone https://github.com/hortonworks-gallery/iotdemo-service.git   /var/lib/ambari-server/resources/stacks/HDP/${hdp_ver}/services/IOTDEMO   
	#sudo git clone https://github.com/hortonworks-gallery/ambari-zeppelin-service.git  /var/lib/ambari-server/resources/stacks/HDP/2.4/services/ZEPPELINDEMO
fi
sudo git clone https://github.com/abajwa-hw/solr-stack.git   /var/lib/ambari-server/resources/stacks/HDP/${hdp_ver}/services/SOLRDEMO
sudo git clone https://github.com/abajwa-hw/ambari-nifi-service /var/lib/ambari-server/resources/stacks/HDP/${hdp_ver}/services/NIFIDEMO


#update role_command_order
cat << EOF > custom_order.json
    "SOLR_MASTER-START" : ["ZOOKEEPER_SERVER-START"],
    "NIFI_MASTER-START" : ["ZOOKEEPER_SERVER-START"],    
EOF
  
if [ "${install_iotdemo}" = true  ]; then
  echo '    "IOTDEMO_MASTER-START" : ["ZOOKEEPER_SERVER-START", "NAMENODE-START", "DATANODE-START", "NODEMANAGER-START", "RESOURCEMANAGER-START", "HIVE_SERVER-START", "WEBHCAT_SERVER-START", "HBASE_MASTER-START", "HBASE_REGIONSERVER-START","KAFKA_BROKER-START","STORM_REST_API-START" ],' >>  custom_order.json
fi

#if [ "${hdp_ver}" = "2.4" ]; then
#  echo '    "ZEPPELIN_MASTER-START": ["NAMENODE-START", "DATANODE-START"],' >>  custom_order.json
#fi

sed -i.bak '/"dependencies for all cases",/ r custom_order.json' /var/lib/ambari-server/resources/stacks/HDP/${hdp_ver}/role_command_order.json

if [ "${install_nifisolr_on_all_nodes}" = true ]; then
  advisor="/var/lib/ambari-server/resources/stacks/HDP/2.0.6/services/stack_advisor.py"
  cp $advisor "$advisor.bak"
  sed -i.bak  "s#return \['ZOOKEEPER_SERVER', 'HBASE_MASTER'\]#return \['ZOOKEEPER_SERVER', 'HBASE_MASTER', 'NIFI_MASTER', 'SOLR_MASTER'\]#" $advisor
  sed -i.bak  "s#\('ZOOKEEPER_SERVER': {\"min\": 3},\)#\1\n      'NIFI_MASTER': {\"min\": $host_count}, 'SOLR_MASTER': {\"min\": $host_count},#g"  $advisor
fi


service ambari-server restart
sleep 20

yum install -y python-argparse


cd ~/ambari-bootstrap/deploy

#temporary - patch hardcoded stack bug
#git pull origin pull/25/head
#git reset --hard b2e5cf5

#download nifi flow
twitter_flow=$(curl -L ${nifi_flow})
#change kafka broker string for Ambari to replace later
twitter_flow=$(echo ${twitter_flow}  | sed 's/demo.hortonworks.com:6667/\{\{kafka_broker_host\}\}:6667/g')

#include LLAP in custom configs only for 2.5
#if ([ "${hdp_ver}" = "2.5" ] && [ "${enable_llap}" = true ]); then
#	llap_config='"hive-interactive-env": {  "enable_hive_interactive": "true", "hive.server2.tez.default.queues": "llap", "llap_queue_capacity": "75" },'
#fi

if ([ "${hdp_ver}" = "2.5" ] && [ "${install_iotdemo}" = true ]); then
	iot_config="\"demo-config\": {  \"demo.ambari_username\": \"${service_user}\", \"demo.ambari_password\": \"${service_password}\" },"
fi


#custom configs
cat << EOF > configuration-custom.json
{
  "configurations" : {

    ${llap_config}
    ${iot_config}     
    "hadoop-env": {
        "namenode_heapsize": "2048m"
    },       
    "hdfs-site": {
        "dfs.replication": "1"
    },    
    "core-site": {
        "hadoop.proxyuser.root.hosts": "*"
    },    
    "solr-config": {
        "solr.download.location": "HDPSEARCH",
        "solr.cloudmode": "true",
        "solr.demo_mode": "true"
    },
     "nifi-flow-env" : {
        "properties_attributes" : { },
        "properties" : {
            "content" : "${twitter_flow}"
        }
     }    
  }
}
EOF


#nifi 1.0 needs JRE 8 to be available
yum install -y java-1.8.0-openjdk

if [ "${install_nifidemo}" = true  ]; then
	export ambari_services="${ambari_services} NIFI SOLR"
fi
if [ "${install_iotdemo}" = true  ]; then
	export ambari_services="${ambari_services} HBASE PHOENIX KAFKA STORM IOTDEMO"
fi
if [ "${hdp_ver}" = "2.5" ]; then
	export ambari_services="${ambari_services} LOGSEARCH AMBARI_INFRA ZEPPELIN SLIDER"
	export recommendation_strategy="ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES"
fi

export ambari_stack_name=HDP
export ambari_stack_version=${hdp_ver}
export ambari_password="${ambari_password}"
bash ./deploy-recommended-cluster.bash

echo "Waiting for cluster to be installed..."
sleep 5

#wait until cluster deployed
ambari_pass="${ambari_password}" source ~/ambari-bootstrap/extras/ambari_functions.sh
ambari_configs
ambari_wait_request_complete 1


export HOST=$(hostname -f)

#Turn on maintenance mode for Grafana to prevent startup issues while restarting cluster
curl -u ${service_user}:${service_password} -H X-Requested-By:blah -X PUT -d '{"RequestInfo": {"context" :"Turn on Maintenance Mode for Grafana"}, "Body": {"HostRoles": {"maintenance_state": "ON"}}}' http://localhost:8080/api/v1/clusters/${cluster_name}/hosts/${HOST}/host_components/METRICS_GRAFANA

# If Zeppelin was successfully installed, update the demo notebooks
zeppelin_missing=$(curl -u ${service_user}:${service_password} -H  X-Requested-By:blah http://localhost:8080/api/v1/clusters/$cluster_name/services/ZEPPELIN | grep "Service not found" | wc -l)
if [ "$zeppelin_missing" -eq "0" ]; then
   echo "Updating Zeppelin notebooks"
   sudo curl -sSL https://raw.githubusercontent.com/hortonworks-gallery/zeppelin-notebooks/master/update_all_notebooks.sh | sudo -E sh 

  #update zeppelin configs by uncommenting admin user, enabling sessionManager/securityManager, switching from anon to authc
  cd /var/lib/ambari-server/resources/scripts/
  ./configs.sh -u ${service_user} -p ${service_password} get localhost ${cluster_name} zeppelin-env   | sed -e '1,3d' \
    -e "/^\"shiro_ini_content\" : / s:#admin = password1:admin = ${ambari_password}:"  \
    -e "/^\"shiro_ini_content\" : / s:#sessionManager:sessionManager:" \
    -e "/^\"shiro_ini_content\" : / s:#securityManager:securityManager:" \
    -e "/^\"shiro_ini_content\" : / s:#securityManager:securityManager:" \
    -e "/^\"shiro_ini_content\" : / s:/\*\* = anon:#/\*\* = anon:" \
    -e "/^\"shiro_ini_content\" : / s:#/\*\* = authc:/\*\* = authc:"  > /tmp/zeppelin-env.json


  #write updating configs  
  ./configs.sh -u ${service_user} -p ${service_password} set localhost ${cluster_name} zeppelin-env /tmp/zeppelin-env.json

  #restart Zeppelin
  sudo curl -u ${service_user}:${service_password} -H 'X-Requested-By: blah' -X POST -d "
{
   \"RequestInfo\":{
      \"command\":\"RESTART\",
      \"context\":\"Restart Zeppelin\",
      \"operation_level\":{
         \"level\":\"HOST\",
         \"cluster_name\":\"${cluster_name}\"
      }
   },
   \"Requests/resource_filters\":[
      {
         \"service_name\":\"ZEPPELIN\",
         \"component_name\":\"ZEPPELIN_MASTER\",
         \"hosts\":\"${HOST}\"
      }
   ]
}" http://localhost:8080/api/v1/clusters/$cluster_name/requests  

fi  


echo "Creating home dirs for admin, root, anonymous"
for user in admin root anonymous; do
  sudo -u hdfs hdfs dfs -mkdir /user/$user
  sudo -u hdfs hdfs dfs -chown $user /user/$user
done

#setup stage dir/table for tweets
sudo -u hdfs hdfs dfs -mkdir /tmp/tweets_staging
sudo -u hdfs hdfs dfs -chmod -R 777 /tmp/tweets_staging

hive -e 'create table if not exists tweets_text_partition(
  tweet_id bigint, 
  created_unixtime bigint, 
  created_time string, 
  displayname string, 
  msg string,
  fulltext string
)
row format delimited fields terminated by "|"
location "/tmp/tweets_staging";'

echo "Importing sample foodmart dataset into Hive..."
curl -sSL https://raw.githubusercontent.com/hortonworks/tutorials/hdp-2.5/tutorials/hortonworks/learning-the-ropes-of-the-hortonworks-sandbox/Foodmart_Data/load_foodmart_data.sh | sudo -E sh

#remove zeppelin view as it doesn't work on AWS
sudo rm -f /var/lib/ambari-server/resources/views/zeppelin-view-*

#register storm view
#if ([ "${hdp_ver}" = "2.5" ] && [ "${install_iotdemo}" = true ]); then
#
# # install latest storm view jar (if not already installed)
#  if [ ! -f /var/lib/ambari-server/resources/views/storm-view-0.1.0.0.jar ]; then
#    cd /var/lib/ambari-server/resources/views/
#    rm -f storm-view-2.*.jar
#    rm -rf work/Storm_Monitoring*    
#    wget https://hipchat.hortonworks.com/files/1/1907/zF4FiDbf3sMXsjy/storm-view-0.1.0.0.jar
#    chmod 777 storm-view-0.1.0.0.jar
#  fi

#  curl -ksSu ${service_user}:${service_password} -H x-requested-by:blah http://localhost:8080/api/v1/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X DELETE
#  #Instantiate Storm view

#body=$(cat <<EOF
#{
#  "ViewInstanceInfo": {
#    "instance_name": "StormAdmin", "label": "Storm View", "description": "Storm View",
#    "visible": true,
#    "properties": {
#      "storm.host" : "${HOST}",
#      "storm.port" : "8744"
#    }
#  }
#}
#EOF
#)

#  echo "Submitting request to register Storm view: ${body}"
#  echo "${body}" | curl -ksSu ${service_user}:${service_password} -H x-requested-by:blah http://localhost:8080/api/v1/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X POST -d @-
#  echo "Restarting Ambari"
#  sudo ambari-server restart
#  sleep 15
#fi

if ([ "${hdp_ver}" = "2.5" ] && [ "${install_iotdemo}" = true ]); then
  sudo ambari-server restart
  sleep 15
  
  echo "To complete IOT-Demo setup, please replace all storm log4j-2.1*.jars with log4j*2.6.2.jars in lib dir. Run below on all nodes where Storm is installed."
  echo "sudo mkdir ~/oldjars"
  echo "sudo mv /usr/hdp/2.5*/storm/lib/log4j*-2.1.jar ~/oldjars"
  echo "sudo cp /var/lib/ambari-agent/cache/host_scripts/*.jar  /usr/hdp/2.5*/storm/lib/"

fi

#clear startup log before creating image
rm -f /var/log/hdp_startup.log

echo "Setup complete! Access Ambari UI on port 8080."
