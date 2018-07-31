#!/bin/bash
set -e

docker run --name ovirt-postgres -e POSTGRES_PASSWORD=engine -e POSTGRES_USER=engine -e POSTGRES_DB=engine --rm -d wooshot/ovirt-psql
docker run --name ovirt-dwh -e POSTGRES_PASSWORD=ovirt_engine_history -e POSTGRES_USER=ovirt_engine_history -e POSTGRES_DB=ovirt_engine_history --rm -d wooshot/ovirt-psql
docker run --name ovirt-engine  --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --link ovirt-postgres:postgres --link ovirt-dwh:ovirt-dwh --network="bridge" --add-host="qcvm.local:127.0.0.1" --rm -p 8443:8443 -d wooshot/oe4.2

sleep 5
docker exec -ti ovirt-engine bash /entrypoint.sh