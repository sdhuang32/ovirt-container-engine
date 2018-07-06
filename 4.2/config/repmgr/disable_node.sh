#!/bin/bash

usage() {
    echo "usage: $0 node_ip"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

TARGET_HOST=$1

if [ "${TARGET_HOST}" = "localhost" ]; then
    systemctl stop ovirt-engine
    systemctl stop ovirt-engine-dwhd
    pid=$(ps ax | grep ovirt-fence-kdump-listener.py | grep -v grep | awk '{print $1}')
    if [ -n "${pid}" ]; then
        kill ${pid}
    fi
    # if we are testing a switchover, then DON'T stop postgresql;
    # otherwise a failover, then DO stop postgresql.
    #systemctl stop rh-postgresql95-postgresql
    echo "stopping postgresql server..."
    su - postgres -c "pg_ctl -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -m immediate stop"
else
    ssh "${TARGET_HOST}" "
    systemctl stop ovirt-engine
    systemctl stop ovirt-engine-dwhd
    pid=\$(ps ax | grep ovirt-fence-kdump-listener.py | grep -v grep | awk '{print \$1}')
    if [ -n \"\${pid}\" ]; then
        kill \${pid}
    fi
    # if we are testing a switchover, then DON'T stop postgresql;
    # otherwise a failover, then DO stop postgresql.
    #systemctl stop rh-postgresql95-postgresql
    su - postgres -c \"pg_ctl -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -m immediate stop\"
    "
fi
