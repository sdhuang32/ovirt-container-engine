#!/bin/bash

DEPLOY_LOG="/var/log/deploy-container-postgres.log"
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

timelog "Start to deploy QCS container postgresql."
# setup repmgr conf
NODE_ADDRESS=$(cat /etc/hosts | grep $(hostname) | awk '{print $1}')
timelog -n "Setting repmgr conf for node #${NODE_NUMBER}, address ${NODE_ADDRESS}... "
sed -i "s/NODE_NUMBER/${NODE_NUMBER}/g" /etc/repmgr.conf
sed -i "s/NODE_NAME/node${NODE_NUMBER}/g" /etc/repmgr.conf
sed -i "s/NODE_ADDRESS/${NODE_ADDRESS}/g" /etc/repmgr.conf
echo "done."

# setup repmgrd service
timelog -n "Setting systemd config for repmgrd... "
sed -i 's/\/etc\/repmgr\/9.5\/repmgr.conf/\/etc\/repmgr.conf/g' /usr/lib/systemd/system/rh-postgresql95-repmgr.service
systemctl daemon-reload
PID_FILE_DIR=$(cat /usr/lib/tmpfiles.d/rh-postgresql95-repmgr.conf | awk '{print $2}')
PID_FILE_DIR=${PID_FILE_DIR////\\/}
sed -i "s/\/var\/run\/repmgr\/repmgrd-9.5.pid/${PID_FILE_DIR}\/repmgrd-9.5.pid/g" /usr/lib/systemd/system/rh-postgresql95-repmgr.service
echo "done."

# This script is expected to be exeuted when deploy
# a new ovirt-postgres container, and right after boot.
# So the postgresql and repmgr service should not
# already running at this time.
if [ $# -eq 1 ]; then
    timelog "This node is master node. Start postgresql service and register into repmgr DB."
    systemctl start rh-postgresql95-postgresql & 2>&1
    # make sure postgresql is ready to accept connections
    until su - postgres -c pg_isready 2>&1
    do
      timelog "Waiting for postgres..."
      sleep 2;
    done
    su - postgres -c "repmgr master register"
    timelog "Finished master node registration. Detail logs:"
    echo "$(cat /var/log/repmgr/repmgr.log)"
else
    timelog "This node is standby node. Clone postgresql data from master and register into repmgr DB."
    rm -rf /var/opt/rh/rh-postgresql95/lib/pgsql/data/* 2>&1
    su - postgres -c "repmgr -h ${MASTER_NODE} -U repmgr -d repmgr -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -f /etc/repmgr.conf standby clone"
    timelog "Finished postgresql data clone."
    timelog "Start postgresql service."
    systemctl start rh-postgresql95-postgresql & 2>&1
    until su - postgres -c pg_isready 2>&1
    do
      timelog "Waiting for postgres..."
      sleep 2;
    done
    su - postgres -c "repmgr standby register"
    timelog "Finished standby node registration. Detail logs for standby clone and registration:"
    echo "$(cat /var/log/repmgr/repmgr.log)"
    timelog "Start repmgrd service."
    systemctl start rh-postgresql95-repmgr 2>&1
fi
timelog "QCS container postgresql successfully deployed."
