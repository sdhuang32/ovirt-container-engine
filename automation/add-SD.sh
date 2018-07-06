#!/bin/bash
set -e

CMD_GETCFG="/sbin/getcfg"

echo "Create Volumes"
result=$(/bin/cat /proc/mounts | /bin/awk '{ if( $3 == "ceph" ) print $2}' | /bin/grep QTS_VOL | /bin/grep -v .ovirt | /bin/grep -v vdsm | /usr/bin/head -n 1)
cephfs_path=$(/bin/mount | /bin/grep $result | /bin/awk '{print $1}')

/bin/echo cephfs path: ${cephfs_path}

if [ "x${cephfs_path}" != "x" ] ;then
    /bin/mkdir -p ${cephfs_path}/.ovirt_data_domain
    /bin/mkdir -p ${cephfs_path}/.ovirt_iso_domain
    /bin/mkdir -p ${cephfs_path}/.ovirt_template
fi

bridge_name="br-provider"
NAS_NAME=$(hostname -s)
CEPH_CLUSTER_IP=$($CMD_GETCFG Cephfs_1 monHost -f /etc/config/qcc_storage.conf | /bin/sed 's/,/:6789,/g')
VOL_NAME=$(/bin/grep Vol_1 /etc/config/qcc_storage.conf | sed -e 's/^\[//g' -e 's/\]$//g' | awk -F_ '{print $1"_"$2}')
CEPH_KEY=$($CMD_GETCFG ${VOL_NAME} clientAdminKey -f /etc/config/qcc_storage.conf )

/bin/echo nas name: ${NAS_NAME}
/bin/echo ceph cluster ip: ${CEPH_CLUSTER_IP}
/bin/echo ceph key: ${CEPH_KEY}

system-docker exec -ti ovirt-engine bash /root/bin/post_init_ovirte.sh ${NAS_NAME} ${CEPH_CLUSTER_IP} ${CEPH_KEY}
