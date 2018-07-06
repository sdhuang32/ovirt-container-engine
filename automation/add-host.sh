#!/bin/bash
set -e

if [ $# -ne 2 ]; then
    echo "Usage: add-host.sh <host_ip> <hostname>"
    exit
fi

IP=$1
host=$2

echo IP: ${IP}
echo hostname: ${host}
system-docker exec -ti ovirt-engine bash /root/bin/init_ovirte.sh ${IP} ${host}
