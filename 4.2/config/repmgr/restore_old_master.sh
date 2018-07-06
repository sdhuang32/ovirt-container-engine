#!/bin/bash
# This script is used after failover or switchover
# to restore the old master node as a new standby

usage() {
    echo "usage: $0 new_master old_master"
}

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

NEW_MASTER_HOST=$1
OLD_MASTER_HOST=$2

if [ "${OLD_MASTER_HOST}" = "localhost" ]; then
    IP=$(grep "$(hostname)" /etc/hosts | awk '{print $1}')
    OLD_MASTER_ID=$(psql -h "${NEW_MASTER_HOST}" -U repmgr -d repmgr -c "select id from repmgr_qcs.repl_nodes where conninfo like '%${IP}%';" | tail -n 3 | head -n 1 | awk '{print $1}')
else
    OLD_MASTER_ID=$(psql -h "${NEW_MASTER_HOST}" -U repmgr -d repmgr -c "select id from repmgr_qcs.repl_nodes where conninfo like '%${OLD_MASTER_HOST}%';" | tail -n 3 | head -n 1 | awk '{print $1}')
fi
echo "OLD_MASTER_ID = ${OLD_MASTER_ID}"

psql -h "${NEW_MASTER_HOST}" -U repmgr -d repmgr -c "DELETE FROM repmgr_qcs.repl_nodes WHERE id = ${OLD_MASTER_ID};"

if [ "${OLD_MASTER_HOST}" = "localhost" ]; then
    systemctl stop ovirt-engine
    systemctl stop ovirt-engine-dwhd
    su - postgres -c "pg_ctl -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -m immediate stop"
    rm -rf /var/opt/rh/rh-postgresql95/lib/pgsql/data/*
    su - postgres -c "repmgr -h ${NEW_MASTER_HOST} -U repmgr -d repmgr -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -f /etc/repmgr.conf standby clone"
    systemctl restart rh-postgresql95-postgresql
    su - postgres -c "repmgr standby register"
    systemctl restart rh-postgresql95-repmgr
else
ssh "${OLD_MASTER_HOST}" "
systemctl stop ovirt-engine
systemctl stop ovirt-engine-dwhd
su - postgres -c \"pg_ctl -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -m immediate stop\"
rm -rf /var/opt/rh/rh-postgresql95/lib/pgsql/data/*
su - postgres -c \"repmgr -h ${NEW_MASTER_HOST} -U repmgr -d repmgr -D /var/opt/rh/rh-postgresql95/lib/pgsql/data/ -f /etc/repmgr.conf standby clone\"
systemctl restart rh-postgresql95-postgresql
su - postgres -c \"repmgr standby register\"
systemctl restart rh-postgresql95-repmgr
"
fi
