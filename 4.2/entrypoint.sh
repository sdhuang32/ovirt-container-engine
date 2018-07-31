#!/bin/bash

DEPLOY_LOG="/var/log/ovirt-engine/deploy-container-engine.log"
time_format="+%Y/%m/%d %H:%M:%S"

timelog() {
    _time=$(/bin/date "${time_format}" | sed -e 's/\r//g')
    if [ "$1" = "-n" ]; then
        echo -n "[${_time}] $2"
    else
        echo "[${_time}] $1"
    fi
}

usage(){
    echo "usage: $0 <node number>"
    echo "  <node number>: integer from 1 to upper bound.>"
}

. /etc/profile

NODE_NUMBER=""
if [ $# -ne 1 ]; then
    usage
    exit 1
fi
NODE_NUMBER=$1

timelog "Start to deploy QCS Container engine."
# setup repmgr conf
NODE_ADDRESS=$(cat /etc/hosts | grep postgres | awk '{print $1}')
timelog -n "Setting repmgr conf for node #${NODE_NUMBER}, container postgresql address ${NODE_ADDRESS}... "
sed -i "s/NODE_NUMBER/${NODE_NUMBER}/g" /etc/repmgr.conf
sed -i "s/NODE_NAME/node${NODE_NUMBER}/g" /etc/repmgr.conf
sed -i "s/NODE_ADDRESS/${NODE_ADDRESS}/g" /etc/repmgr.conf
echo "done."

if [ -d /root/ovirt-engine-pki ]; then
    timelog -n "Install ovirt-engine pki... "
    rm -rf /etc/pki/ovirt-engine 2> /dev/null
    cp -rpT /root/ovirt-engine-pki /etc/pki/ovirt-engine
    echo "done."

    timelog "Checking postgresql and (if ready) start monitor daemon for engine service."
    # make sure postgresql is ready to accept connections
    until su - postgres -c "pg_isready -h postgres" 2>&1
    do
      timelog "Waiting for postgres..."
      sleep 2;
    done
    timelog -n "Start monitor daemon for engine service..."
    auto_start_engine.sh &
    crontab /etc/cron.d/auto-start-engine-cron
    echo "done."
    timelog "QCS Container engine successfully deployed."
else
    timelog "/root/ovirt-engine-pki DOES NOT EXIST!"
fi
