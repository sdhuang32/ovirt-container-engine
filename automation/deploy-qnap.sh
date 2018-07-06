#!/bin/bash

#DEPLOY_LOG="/var/log/ovirt-engine/deploy-container-engine.log"
#time_format="+%Y/%m/%d %H:%M:%S"

#timelog() {
#    _time=$(/bin/date "${time_format}" | sed -e 's/\r//g')
#    if [ "$1" = "-n" ]; then
#        echo -n "[${_time}] $2" >> ${DEPLOY_LOG}
#    else
#        echo "[${_time}] $1" >> ${DEPLOY_LOG}
#    fi
#}

usage(){
    echo "usage: $0 <node number> <master node hostname/IP>"
    echo "  <node number>: integer from 1 to upper bound.>"
    echo "  <master node hostname/IP>: if not specified, this node will be treated as master.>"
}

NODE_NUMBER=""
MASTER_NODE=""
if [ $# -lt 1 -o $# -gt 2 ]; then
    usage
    exit 1
elif [ $# -eq 2 ]; then
    MASTER_NODE="$2"
fi
NODE_NUMBER=$1

set -e

QCS_REGISTRY="192.168.81.147:3200"
REPO_NAME="daily-qcs-ovirt-engine"
year=$(date '+%Y')
month=$(date '+%m')
day=$(date '+%d')

system-docker pull ${QCS_REGISTRY}/${REPO_NAME}:${year}${month}${day}
echo "Create Container"
system-docker run --name ovirt-engine  --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --network="bridge" -p 8443:8443 -d ${QCS_REGISTRY}/${REPO_NAME}:${year}${month}${day}

echo "Sleep 3 seconds for container running"
sleep 3
if [ $# -eq 1 ]; then
    system-docker exec -tid ovirt-engine bash /entrypoint.sh ${NODE_NUMBER}
else
    system-docker exec -tid ovirt-engine bash /entrypoint.sh ${NODE_NUMBER} ${MASTER_NODE}
fi


IP=$(ifconfig | grep -A 1 'eth1' | tail -1 | awk '{print$2}')
echo ${IP:5}
