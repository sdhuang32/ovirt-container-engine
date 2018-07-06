#!/bin/bash

DEPLOY_LOG="/var/log/ovirt-engine/deploy-container-engine.log"
time_format="+%Y/%m/%d %H:%M:%S"

timelog() {
    _time=$(/bin/date "${time_format}" | sed -e 's/\r//g')
    if [ "$1" = "-n" ]; then
        echo -n "[${_time}] $2" >> ${DEPLOY_LOG}
    else
        echo "[${_time}] $1" >> ${DEPLOY_LOG}
    fi
}

usage(){
    echo "usage: $0 <node number> <master node hostname/IP>"
    echo "  <node number>: integer from 1 to upper bound.>"
    echo "  <master node hostname/IP>: if not specified, this node will be treated as master.>"
}

. /etc/profile

NODE_NUMBER=""
MASTER_NODE=""
if [ $# -lt 1 -o $# -gt 2 ]; then
    usage
    exit 1
elif [ $# -eq 2 ]; then
    MASTER_NODE="$2"
fi
NODE_NUMBER=$1

# setup repmgr conf
sed -i "s/NODE_NUMBER/${NODE_NUMBER}/g" /etc/repmgr.conf
sed -i "s/NODE_NAME/node${NODE_NUMBER}/g" /etc/repmgr.conf
NODE_ADDRESS=$(cat /etc/hosts | grep $(hostname) | awk '{print $1}')
sed -i "s/NODE_ADDRESS/${NODE_ADDRESS}/g" /etc/repmgr.conf

if [ -d /root/ovirt-engine-pki ]; then
    rm -rf /etc/pki/ovirt-engine 2> /dev/null
    cp -rpT /root/ovirt-engine-pki /etc/pki/ovirt-engine

    # setup repmgrd service
    sed -i 's/\/etc\/repmgr\/9.5\/repmgr.conf/\/etc\/repmgr.conf/g' /usr/lib/systemd/system/rh-postgresql95-repmgr.service
    systemctl daemon-reload
    PID_FILE_DIR=$(cat /usr/lib/tmpfiles.d/rh-postgresql95-repmgr.conf | awk '{print $2}')
    PID_FILE_DIR=${PID_FILE_DIR////\\/}
    sed -i "s/\/var\/run\/repmgr\/repmgrd-9.5.pid/${PID_FILE_DIR}\/repmgrd-9.5.pid/g" /usr/lib/systemd/system/rh-postgresql95-repmgr.service
    systemctl enable rh-postgresql95-repmgr

    if [ $# -eq 1 ]; then
        # make sure postgresql is ready to accept connections
        until su - postgres -c pg_isready
        do
          echo "Waiting for postgres..."
          sleep 2;
        done
        systemctl start ovirt-engine
        su - postgres -c "repmgr master register"
    else
        disable_node.sh localhost
        rm -rf /var/opt/rh/rh-postgresql95/lib/pgsql/data/*
        su - postgres -c "repmgr -h ${MASTER_NODE} -U repmgr -d repmgr -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -f /etc/repmgr.conf standby clone"
        systemctl start rh-postgresql95-postgresql
        su - postgres -c "repmgr standby register"

        systemctl start rh-postgresql95-repmgr
        auto_start_engine.sh &
    fi
    crontab /etc/cron.d/auto-start-engine-cron
else
    timelog "/root/ovirt-engine-pki DOES NOT EXIST!"
fi
