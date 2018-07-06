#!/bin/bash

QCS_REGISTRY="192.168.81.147:3200"
CONTAINER_NAME="daily-qcs-ovirt-engine"
KS_SOURCE="10.19.253.2:/Firmware_Release"
RD3_SOURCE="192.168.81.147:/Public"
MOUNT_POINT="/mnt/target"
year=$(date '+%Y')
month=$(date '+%b')
month_num=$(date '+%m')
day=$(date '+%d')
RPMS_DIR=""

if [ ! -d ${MOUNT_POINT} ]; then
    mkdir ${MOUNT_POINT}
fi
if [ -z "$(mount | grep ${MOUNT_POINT})" ]; then
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
fi

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

echo "*** start to build daily container engine image ***"
docker build --rm -t local/${CONTAINER_NAME}:${year}${month_num}${day} ${BASE_DIR}/../4.2/
docker run --name ${CONTAINER_NAME} --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --network="bridge" --add-host="qcvm.local:127.0.0.1" -p 8443:8443 --rm -d local/${CONTAINER_NAME}:${year}${month_num}${day}
docker exec -ti ${CONTAINER_NAME} bash /qcs-engine-setup.sh
docker exec -ti ${CONTAINER_NAME} cp -rp /etc/pki/ovirt-engine /root/ovirt-engine-pki
CONTAINER_ID=$(docker ps | grep ${CONTAINER_NAME} | awk '{print $1}')
docker commit "${CONTAINER_ID}" local/daily-push
docker tag local/daily-push ${QCS_REGISTRY}/${CONTAINER_NAME}:${year}${month_num}${day}
docker push ${QCS_REGISTRY}/${CONTAINER_NAME}:${year}${month_num}${day}

docker stop ${CONTAINER_NAME}
docker rmi ${QCS_REGISTRY}/${CONTAINER_NAME}:${year}${month_num}${day}
docker rmi local/daily-push
docker rmi local/${CONTAINER_NAME}:${year}${month_num}${day}
echo "*** finished. ***"
