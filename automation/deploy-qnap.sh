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
    echo "usage: $0 -i <node index> [-m master node hostname/IP] [-d QPKG date]"
    echo "  <node index>: integer from 1 to upper bound."
    echo "  [master node hostname/IP]: if not specified, this node will be treated as master."
    echo "  [QPKG date]: if not specified, use date of today according to this node."
    echo "  e.g."
    echo "      $0 -i 1"
    echo "      $0 -i 1 -d 20180707"
    echo "      $0 -i 2 -m 10.0.5.2 -d 20180707"

    exit 1
}

NODE_NUMBER=""
MASTER_NODE=""
QPKG_DATE=""
while getopts ":i:m:d:" arg; do
    case "${arg}" in
        i)
            NODE_NUMBER=${OPTARG}
            ;;
        m)
            MASTER_NODE=${OPTARG}
            ;;
        d)
            QPKG_DATE=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -gt 0 ]; then
    usage
fi

if [ -z "${NODE_NUMBER}" ]; then
    usage
fi

set -e

QCS_REGISTRY="192.168.81.147:3200"
ENGINE_REPO_NAME="daily-qcs-ovirt-engine-separated"
POSTGRES_REPO_NAME="daily-qcs-postgres-separated"

year=$(date '+%Y')
month=$(date '+%m')
day=$(date '+%d')
if [ -n "${QPKG_DATE}" ]; then
    year=$(date --date="${QPKG_DATE}" "+%Y")
    month=$(date --date="${QPKG_DATE}" "+%m")
    day=$(date --date="${QPKG_DATE}" "+%d")
fi

system-docker pull ${QCS_REGISTRY}/${POSTGRES_REPO_NAME}:${year}${month}${day}
system-docker pull ${QCS_REGISTRY}/${ENGINE_REPO_NAME}:${year}${month}${day}
echo "Create Container"
system-docker run --name ovirt-postgres --privileged -d ${QCS_REGISTRY}/${POSTGRES_REPO_NAME}:${year}${month}${day}
system-docker run --name ovirt-engine --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --link ovirt-postgres:postgres --network="bridge" --add-host="qcvm.local:127.0.0.1" -p 8443:8443 -d ${QCS_REGISTRY}/${ENGINE_REPO_NAME}:${year}${month}${day}

echo "Sleep 3 seconds for container running"
sleep 3
if [ -z ${MASTER_NODE} ]; then
    system-docker exec -t ovirt-postgres bash /entrypoint.sh ${NODE_NUMBER}
    sleep 1
    system-docker exec -t ovirt-engine bash /entrypoint.sh ${NODE_NUMBER}
else
    system-docker exec -t ovirt-postgres bash /entrypoint.sh ${NODE_NUMBER} ${MASTER_NODE}
    sleep 1
    system-docker exec -t ovirt-engine bash /entrypoint.sh ${NODE_NUMBER}
fi

