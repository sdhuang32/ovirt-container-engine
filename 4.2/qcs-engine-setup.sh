#!/bin/bash

set -e

cp -f /answers.conf.in /answers.conf
echo OVESETUP_DB/user=str:$POSTGRES_USER >> /answers.conf
echo OVESETUP_DB/password=str:$POSTGRES_PASSWORD >> /answers.conf
echo OVESETUP_DB/database=str:$POSTGRES_DB >> /answers.conf
echo OVESETUP_DB/host=str:$POSTGRES_HOST >> /answers.conf
echo OVESETUP_DB/port=str:$POSTGRES_PORT >> /answers.conf
echo OVESETUP_ENGINE_CONFIG/fqdn=str:$OVIRT_FQDN >> /answers.conf
echo OVESETUP_CONFIG/fqdn=str:$OVIRT_FQDN >> /answers.conf
echo OVESETUP_CONFIG/adminPassword=str:$OVIRT_PASSWORD >> /answers.conf
echo OVESETUP_PKI/organization=str:$OVIRT_PKI_ORGANIZATION >> /answers.conf
echo OVESETUP_CONFIG/adminUserId=str:$OVIRT_ADMIN_UID >> /answers.conf

# Copy pki template files into original template location.
# Mounts on kubernetes hide the original files in the image.
cp -a --no-preserve=ownership /etc/pki/ovirt-engine.tmpl/* /etc/pki/ovirt-engine/

# Wait for postgres
#dockerize -wait tcp://${POSTGRES_HOST}:${POSTGRES_PORT} -timeout 1m
#dockerize -wait tcp://ovirt-dwh:5432 -timeout 1m

# engine-setup required
export PGPASSWORD=$POSTGRES_PASSWORD
# psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"

engine-setup --config=/answers.conf --offline

if [ -n "$SPICE_PROXY" ]; then
  engine-config -s SpiceProxyDefault=$SPICE_PROXY
fi

# # SSO configuration
echo SSO_ALTERNATE_ENGINE_FQDNS="\"$SSO_ALTERNATE_ENGINE_FQDNS\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
echo ENGINE_SSO_SERVICE_SSL_VERIFY_HOST=false >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf

if [ -n "$ENGINE_SSO_AUTH_URL" ]; then
  echo ENGINE_SSO_INSTALLED_ON_ENGINE_HOST=false >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
  echo "ENGINE_SSO_AUTH_URL=\"$ENGINE_SSO_AUTH_URL\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
else
  echo "ENGINE_SSO_AUTH_URL=\"https://${OVIRT_FQDN}/ovirt-engine/sso\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
fi

echo SSO_CALLBACK_PREFIX_CHECK=false >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
echo "ENGINE_SSO_SERVICE_URL=\"https://localhost:8443/ovirt-engine/sso\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
echo "ENGINE_BASE_URL=\"https://${OVIRT_FQDN}/ovirt-engine/\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf
echo "SSO_ENGINE_URL=\"https://localhost:8443/ovirt-engine/\"" >> /etc/ovirt-engine/engine.conf.d/999-ovirt-engine.conf

source /opt/rh/rh-postgresql95/enable
export X_SCLS="`scl enable rh-postgresql95 'echo $X_SCLS'`"

psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE vdc_options set option_value = '$HOST_INSTALL' where option_name = 'InstallVds';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE vdc_options set option_value = '$SSL_ENABLED' where option_name = 'SSLEnabled';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE vdc_options set option_value = '$HOST_USE_IDENTIFIER' where option_name = 'UseHostNameIdentifier';"

psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "ALTER TABLE network ALTER COLUMN name SET DEFAULT 'br-provider';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "ALTER TABLE cluster ALTER COLUMN architecture SET DEFAULT '1';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "ALTER TABLE cluster ALTER COLUMN cpu_name SET DEFAULT 'Intel Haswell-noTSX Family';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "ALTER TABLE cluster ALTER COLUMN additional_rng_sources SET DEFAULT '';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE network SET name = DEFAULT;"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE cluster SET architecture = DEFAULT;"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE cluster SET cpu_name = DEFAULT;"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE cluster SET additional_rng_sources = DEFAULT;"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE cluster SET compatibility_version = '4.0';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE storage_pool SET compatibility_version = '4.0';"
psql $POSTGRES_DB -h $POSTGRES_HOST -p $POSTGRES_PORT  -U $POSTGRES_USER -c "UPDATE network SET vdsm_name = 'br-provider';"

engine-config -s SSLEnabled=$HOST_ENCRYPT
engine-config -s EncryptHostCommunication=$HOST_ENCRYPT
engine-config -s BlockMigrationOnSwapUsagePercentage=$BLOCK_MIGRATION_ON_SWAP_USAGE_PERCENTAGE

# repmgr setup
su - postgres -c "createuser -s repmgr"
su - postgres -c "createdb repmgr -O repmgr"

DATA_DIR="/var/opt/rh/rh-postgresql95/lib/pgsql/data"
cp /root/repmgr.conf.in /etc/repmgr.conf
cp /root/postgresql.replication.conf ${DATA_DIR}/
cp /root/pg_hba.conf.append ${DATA_DIR}/
echo "include 'postgresql.replication.conf'" >> ${DATA_DIR}/postgresql.conf
cat ${DATA_DIR}/pg_hba.conf.append >> ${DATA_DIR}/pg_hba.conf
chmod 600 ${DATA_DIR}/postgresql.replication.conf
chown postgres:postgres ${DATA_DIR}/postgresql.replication.conf

systemctl restart rh-postgresql95-postgresql
# make sure postgresql is ready to accept connections
until su - postgres -c pg_isready
do
  echo "Waiting for postgres..."
  sleep 2;
done
