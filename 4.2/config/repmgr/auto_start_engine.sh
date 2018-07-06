#!/bin/bash

PID_FILE="/var/run/auto_start_engine.pid"
if [ -f ${PID_FILE} ] && kill -0 "$(cat ${PID_FILE})"; then
    exit 0
fi

echo "$$" > ${PID_FILE}
trap "rm -f ${PID_FILE}; exit 0" INT TERM EXIT

while true; do
    LOCAL_IP=$(cat /etc/repmgr.conf | grep conninfo | awk '{print $1}' | awk -F '=' '{print $3}')
    if su - postgres -c pg_isready; then
        MASTER_IP=$(su - postgres -c "repmgr cluster show" 2>/dev/null | grep master | awk '{print $7}' | awk -F '=' '{print $2}')
        if [ "x${MASTER_IP}" != "x" ]; then
            if [ "x${LOCAL_IP}" = "x${MASTER_IP}" ]; then
                if [ -z "$(systemctl status ovirt-engine | grep 'Active: active (running)')" ]; then
                    sleep 2
                    systemctl start ovirt-engine
                fi
            fi
        fi
    fi
    sleep 1
done
