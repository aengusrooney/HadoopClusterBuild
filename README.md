# HadoopClusterBuild

Requires CentOS/RHEL 6/7  

Execute ambari-bootstrap.sh on all nodes, except ambari server 

export ambari_server=[FQDN of ambari-server host]  

curl -sSL https://raw.githubusercontent.com/aengusrooneyhortonworks/HadoopClusterBuild/master/ambari-bootstrap.sh | sudo -E sh ; 

Execute ambari_deploy_hdp.sh on the ambari server only 

export host_count=n #set to number of nodes in your cluster including Ambari-server node 

export hdp_ver=2.5 

export install_nifidemo=true 

export install_iotdemo=true 

curl -sSL https://raw.githubusercontent.com/aengusrooneyhortonworks/HadoopClusterBuild/master/ambari_deploy_hdp.sh | sudo -E sh 

Log on to Ambari UI (port 8080) and monitor the cluster install (admin:BadPass#1) 
