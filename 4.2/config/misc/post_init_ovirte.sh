LOG_FILE=/root/ovirte_log/init_ovirte.log

/bin/echo "[$(date)] [init_ovirte]"  >> ${LOG_FILE}
if [ $# -ne 3 ]; then
    echo "Usage: init_ovirte.sh <host_name> <ceph_ip> <ceph_key>"
    /bin/echo "[$(date)] Usage: init_ovirte.sh <host_name> <ceph_ip> <ceph_key>" >> ${LOG_FILE}
    /bin/echo "$@" >> ${LOG_FILE}
    exit
fi

HOST_NAME=$1
Ceph_cluster_ip=$2
CEPH_KEY=$3

LOG_FILE=/root/ovirte_log/init_ovirte_${HOST_NAME}.log
/bin/echo "[$(date)] HOST_NAME: ${HOST_NAME}" > ${LOG_FILE}
/bin/echo "[$(date)] CEPH_CLUSTER_IP: ${Ceph_cluster_ip}"  >> ${LOG_FILE}
/bin/echo "[$(date)] CEPH_KEY: ${CEPH_KEY}"  >> ${LOG_FILE}

if [ -z "${HOST_NAME}" ]; then
    HOST_NAME="auto_host"
else
    HOST_NAME="auto_${HOST_NAME}"
fi

STORAGE_OPTS="rw,name=admin,secret=${CEPH_KEY},osd_request_timeout=300,noacl"
STORAGE_ADDR="${Ceph_cluster_ip}:6789"

STORAGE_DATA_PATH="/QTS/VOL_1/.ovirt_data_domain"
STORAGE_DATA_NAME="ovirt_data"
STORAGE_ISO_PATH="/QTS/VOL_1/.ovirt_iso_domain"
STORAGE_ISO_NAME="ovirt_iso"
STORAGE_TEMPLATE_PATH="/QTS/VOL_1/.ovirt_template"
STORAGE_TEMPLATE="ovirt_template"

/bin/echo "[$(date)] create data domain" >> ${LOG_FILE}
/usr/bin/ovirt-shell -c -E "add storagedomain --host-name ${HOST_NAME} --type data --storage-type posixfs --storage_format v3 --storage-vfs_type ceph --storage-path ${STORAGE_DATA_PATH} --storage-mount_options \"${STORAGE_OPTS}\" --name ${STORAGE_DATA_NAME} --storage-address ${STORAGE_ADDR}" > /root/ovirte_log/datadomain.log 2>&1
/usr/bin/ovirt-shell -c -E "add storagedomain --parent-datacenter-name Default --name ${STORAGE_DATA_NAME}" >> /root/ovirte_log/datadomain.log 2>&1


/bin/echo "[$(date)] create iso domain" >> ${LOG_FILE}
/usr/bin/ovirt-shell -c -E "add storagedomain --host-name ${HOST_NAME} --type iso --storage-type posixfs --storage-vfs_type ceph --storage-path ${STORAGE_ISO_PATH} --storage-mount_options \"${STORAGE_OPTS}\" --name ${STORAGE_ISO_NAME} --storage-address ${STORAGE_ADDR}" > /root/ovirte_log/isodomain.log 2>&1
/usr/bin/ovirt-shell -c -E "add storagedomain --parent-datacenter-name Default --name ${STORAGE_ISO_NAME}" >> /root/ovirte_log/isodomain.log 2>&1

/bin/echo "[$(date)] create template domain" >> ${LOG_FILE}
/usr/bin/ovirt-shell -c -E "add storagedomain --host-name ${HOST_NAME} --type export --storage-type posixfs --storage-vfs_type ceph --storage-path ${STORAGE_TEMPLATE_PATH} --storage-mount_options \"${STORAGE_OPTS}\" --name ${STORAGE_TEMPLATE} --storage-address ${STORAGE_ADDR}" > /root/ovirte_log/tempdomain.log 2>&1
/usr/bin/ovirt-shell -c -E "add storagedomain --parent-datacenter-name Default --name ${STORAGE_TEMPLATE}" >> /root/ovirte_log/tempdomain.log 2>&1

c=0
STORAGE_STATE=$(ovirt-shell -c -E "show storagedomain --parent-datacenter-name Default --name ${STORAGE_DATA_NAME}" | grep ^status-state | awk '{print $3}')
while [ "x${STORAGE_STATE}" != "xactive" ]; do
    sleep 5
    STORAGE_STATE=$(ovirt-shell -c -E "show storagedomain --parent-datacenter-name Default --name ${STORAGE_DATA_NAME}" | grep ^status-state | awk '{print $3}')
    c=$[$c+1]

    if [ $c -gt 120 ];then
        /bin/echo "[$(date)] init_ovirt fail --> data domain can't get ready (${STORAGE_STATE}). Try Count: ${c}" >> ${LOG_FILE} 2>&1
        exit 1
    fi
done

DATACENTER_STATE=""
c=0
DATACENTER_STATE=$(/usr/bin/ovirt-shell -c -E "show datacenter Default"  | grep ^status-state | grep up | awk '{print $3}')
/bin/echo ${DATACENTER_STATE}
while [ x"${DATACENTER_STATE}" != x"up" ]; do
    sleep 5
    DATACENTER_STATE=$(/usr/bin/ovirt-shell -c -E "show datacenter Default"  | grep ^status-state | grep up | awk '{print $3}')
    c=$[$c+1]

    if [ $c -gt 120 ];then
        /bin/echo "[$(date)] init_ovirt fail --> DATACENTER: Default can not be UP. Try Count: ${c}"  >> ${LOG_FILE}
        exit 1
    fi
done

/usr/bin/ovirt-shell -c -E "show storagedomain --parent-datacenter-name Default --name ${STORAGE_DATA_NAME}" > /root/ovirte_log/data_storage_status.log
/usr/bin/ovirt-shell -c -E "show datacenter Default" > /root/ovirte_log/data_center_status.log

/bin/echo "[$(date)] create cinder provider" >> ${LOG_FILE}
/usr/bin/ovirt-shell -c -E "add openstackvolumeprovider --name qcinder --data_center-name Default --url http://localhost:8776 --requires_authentication 1 --username admin --password admin --tenant_name admin --authentication_url http://localhost:35357/v2.0" > /root/ovirte_log/cinder_provider.log 2>&1

/bin/echo "[$(date)] create virtual QTS template" >> ${LOG_FILE}
/bin/curl -k --user "admin@internal:admin" "https://localhost/virtualqts-cgi/index.cgi?&action=makevqtstemplate&domainname=ovirt_data&clustername=Default&networkname=ovirtmgmt" >> /root/ovirte_log/init_virtualqtstemplate.log 2>&1

/bin/echo "[$(date)] post_init_ovirte successfully"  >> ${LOG_FILE}
