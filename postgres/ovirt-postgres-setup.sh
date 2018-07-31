#!/bin/bash

. /etc/profile
postgresql-setup initdb
echo "listen_addresses = '*'" >> /var/opt/rh/rh-postgresql95/lib/pgsql/data/postgresql.conf
DATA_DIR="/var/opt/rh/rh-postgresql95/lib/pgsql/data"
cp /root/repmgr.conf.in /etc/repmgr.conf
cp /root/postgresql.replication.conf ${DATA_DIR}/
cp /root/pg_hba.conf.append ${DATA_DIR}/
echo "include 'postgresql.replication.conf'" >> ${DATA_DIR}/postgresql.conf
cat ${DATA_DIR}/pg_hba.conf.append >> ${DATA_DIR}/pg_hba.conf
chmod 600 ${DATA_DIR}/postgresql.replication.conf
chown postgres:postgres ${DATA_DIR}/postgresql.replication.conf

# if the master node fails, we need to re-add that node
# into cluster as a standby node, so we disable running
# the postgresql and repmgr service at boot time to
# prevent split-brain condition.
systemctl disable rh-postgresql95-postgresql
systemctl disable rh-postgresql95-repmgr

systemctl start rh-postgresql95-postgresql
# make sure postgresql is ready to accept connections
until su - postgres -c pg_isready
do
  echo "Waiting for postgres..."
  sleep 2;
done
su - postgres -c "psql -c \"create role engine with login encrypted password 'engine';\""
su - postgres -c "psql -c \"create database engine owner engine template template0 encoding 'UTF8' lc_collate 'en_US.UTF-8' lc_ctype 'en_US.UTF-8';\""
su - postgres -c "psql -c \"create role ovirt_engine_history with login encrypted password 'ovirt_engine_history';\""
su - postgres -c "psql -c \"create database ovirt_engine_history owner ovirt_engine_history template template0 encoding 'UTF8' lc_collate 'en_US.UTF-8' lc_ctype 'en_US.UTF-8';\""
# repmgr setup
su - postgres -c "createuser -s repmgr"
su - postgres -c "createdb repmgr -O repmgr"
