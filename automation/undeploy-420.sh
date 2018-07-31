#!/bin/bash
set -e

system-docker stop ovirt-engine ovirt-dwh ovirt-postgres

result=$(/bin/cat /proc/mounts | /bin/awk '{ if( $3 == "ceph" ) print $2}' | /bin/grep QTS_VOL | /bin/grep -v .ovirt | /bin/grep -v vdsm | /usr/bin/head -n 1)
cephfs_path=$(/bin/mount | /bin/grep $result | /bin/awk '{print $1}')

/bin/echo cephfs path: ${cephfs_path}

if [ "x${cephfs_path}" != "x" ] ;then
    /bin/rm -rf ${cephfs_path}/.ovirt_data_domain
    /bin/rm -rf ${cephfs_path}/.ovirt_iso_domain
    /bin/rm -rf ${cephfs_path}/.ovirt_template
fi
