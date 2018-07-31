#!/bin/bash

usage(){
    echo "usage: $0 [-d RPMs date]"
    echo "  [QPKG date]: use RPMs of specified date; if not specified, use date of today according to this node."
    echo "  e.g."
    echo "      $0"
    echo "      $0 20180707"

    exit 1
}

set -e

RPMS_DATE=""
while getopts ":d:" arg; do
    case "${arg}" in
        d)
            QPKG_DATE=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -gt 0 ]; then
    usage
fi

QCS_REGISTRY="192.168.81.147:3200"
ENGINE_CONTAINER_NAME="daily-qcs-ovirt-engine"
POSTGRES_CONTAINER_NAME="daily-qcs-postgres"
KS_SOURCE="10.19.253.2:/Firmware_Release"
RD3_SOURCE="192.168.81.147:/Public"
MOUNT_POINT="/mnt/target"
RPMS_DIR=""
year=$(date '+%Y')
month=$(date '+%b')
month_num=$(date '+%m')
day=$(date '+%d')
if [ -n "${QPKG_DATE}" ]; then
    year=$(date --date="${QPKG_DATE}" "+%Y")
    month=$(date --date="${QPKG_DATE}" "+%b")
    month_num=$(date --date="${QPKG_DATE}" "+%m")
    day=$(date --date="${QPKG_DATE}" "+%d")
fi

if [ ! -d ${MOUNT_POINT} ]; then
    mkdir ${MOUNT_POINT}
fi

if [ -n "$(mount | grep ${MOUNT_POINT})" ]; then
    echo "mounted RPM source folder still here; last build may not complete; build it again from scratch."
    echo -n "umount ${MOUNT_POINT}... "
    result=$(umount ${MOUNT_POINT} 2>&1)
    if [ $? -ne 0 ]; then
        echo "Fail to umount ${MOUNT_POINT}... Force to umount."
        umount -f ${MOUNT_POINT[${count}]} 2>&1
    fi
    echo "done."
fi

# first try the KS's RPMs, and then RD3's if fail to mount.
echo -n "mount ${KS_SOURCE}... "
result=$(mount -t nfs ${KS_SOURCE} ${MOUNT_POINT} 2>&1)
if [ $? -ne 0 ]; then
    echo "Fail to mount ${KS_SOURCE}!"
    echo "(${result})"
    echo -n "mount ${RD3_SOURCE}... "
    result=$(mount -t nfs ${RD3_SOURCE} ${MOUNT_POINT} 2>&1)
    if [ $? -ne 0 ]; then
        echo "Fail to mount ${RD3_SOURCE}!"
        echo "(${result})"
        exit 1
    fi
    RPMS_DIR="${MOUNT_POINT}/QPKG/daily_build/${year}/${month_num}/${day}/.QCVM/rpmbuild-ovirt420/RPMS/"
else
    RPMS_DIR="${MOUNT_POINT}/daily_build/${year}/${month}/${day}/.QCVM/rpmbuild-ovirt420/RPMS/"
fi
echo "done."

echo -n "start to copy RPMs of daily ovirt-engine... "
BASE_DIR=$(dirname $0)
rm -rf ${BASE_DIR}/../4.2/config/ovirt/packages/qcs/noarch
rm -rf ${BASE_DIR}/../4.2/config/ovirt/packages/qcs/repodata
rsync -avpP ${RPMS_DIR}/noarch ${BASE_DIR}/../4.2/config/ovirt/packages/qcs/
rsync -avpP ${RPMS_DIR}/repodata ${BASE_DIR}/../4.2/config/ovirt/packages/qcs/
echo "done."

echo -n "umount ${MOUNT_POINT}... "
result=$(umount ${MOUNT_POINT} 2>&1)
if [ $? -ne 0 ]; then
    echo "Fail to umount ${MOUNT_POINT}... Force to umount."
    umount -f ${MOUNT_POINT[${count}]} 2>&1
fi
echo "done."

echo "*** start to build daily container engine and container postgres image ***"
docker build --rm -t local/${POSTGRES_CONTAINER_NAME} ${BASE_DIR}/../postgres/
docker build --rm -t local/${ENGINE_CONTAINER_NAME} ${BASE_DIR}/../4.2/
docker run --name ${POSTGRES_CONTAINER_NAME} --privileged --rm -d local/${POSTGRES_CONTAINER_NAME}
docker run --name ${ENGINE_CONTAINER_NAME} --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --link ${POSTGRES_CONTAINER_NAME}:postgres --network="bridge" --add-host="qcvm.local:127.0.0.1" -p 8443:8443 --rm -d local/${ENGINE_CONTAINER_NAME}
docker exec -t ${POSTGRES_CONTAINER_NAME} bash /ovirt-postgres-setup.sh
docker exec -t ${ENGINE_CONTAINER_NAME} bash /qcs-engine-setup.sh
docker exec -t ${ENGINE_CONTAINER_NAME} cp -rp /etc/pki/ovirt-engine /root/ovirt-engine-pki
CONTAINER_ID=$(docker ps | grep ${POSTGRES_CONTAINER_NAME} | awk '{print $1}')
docker commit "${CONTAINER_ID}" local/daily-postgres-push
docker tag local/daily-postgres-push ${QCS_REGISTRY}/${POSTGRES_CONTAINER_NAME}-separated:${year}${month_num}${day}
docker push ${QCS_REGISTRY}/${POSTGRES_CONTAINER_NAME}-separated:${year}${month_num}${day}
CONTAINER_ID=$(docker ps | grep ${ENGINE_CONTAINER_NAME} | awk '{print $1}')
docker commit "${CONTAINER_ID}" local/daily-push
docker tag local/daily-push ${QCS_REGISTRY}/${ENGINE_CONTAINER_NAME}-separated:${year}${month_num}${day}
docker push ${QCS_REGISTRY}/${ENGINE_CONTAINER_NAME}-separated:${year}${month_num}${day}

docker stop ${ENGINE_CONTAINER_NAME}
docker rmi ${QCS_REGISTRY}/${ENGINE_CONTAINER_NAME}-separated:${year}${month_num}${day}
docker rmi local/daily-push
docker rmi -f local/${ENGINE_CONTAINER_NAME}
docker stop ${POSTGRES_CONTAINER_NAME}
docker rmi ${QCS_REGISTRY}/${POSTGRES_CONTAINER_NAME}-separated:${year}${month_num}${day}
docker rmi local/daily-postgres-push
docker rmi -f local/${POSTGRES_CONTAINER_NAME}
echo "*** finished. ***"
