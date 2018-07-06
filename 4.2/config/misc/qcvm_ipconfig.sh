#!/bin/bash

ip=$1
network_mask=$2
gateway=$3
dns1=$4
dns2=$5
intf=$6

if [ "x$intf" = "x" ];then
    intf=eth0
fi

QCVM_LOG_FILE='/var/log/qcvm.log'
logger()
{
    message=$1
    time=$(date +%Y%m%d-%H%M%S)
    /bin/echo [$time] $message >> ${QCVM_LOG_FILE}
}
logger "ip $ip"
logger "network_mask $network_mask"
logger "gateway $gateway"
logger "dns1 $dns1"
logger "dns2 $dns2"
logger "inteface $intf"

old_ip=$(/sbin/ifconfig eth0 | /bin/awk '{ print $2}' | /bin/grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
logger "old_ip $old_ip"

/bin/sed "s/\${IP}/${ip}/g;s/\${NET_MASK}/${network_mask}/g" qcvm_ip.template > /root/qcvm_ip

/bin/cp /root/qcvm_ip /etc/sysconfig/network-scripts/ifcfg-eth0

if [ "$gateway" != "none" ];then
    /bin/sed 's/${GATEWAY}/'"${gateway}"'/g'  /root/qcvm_network.template  > /root/qcvm_network
    /bin/cp /root/qcvm_network /etc/sysconfig/network
else
    /bin/sed 's/${GATEWAY}/'""'/g'  /root/qcvm_network.template  > /root/qcvm_network
    /bin/cp /root/qcvm_network /etc/sysconfig/network
fi

logger "restart network start"
/bin/systemctl restart network

/bin/systemctl restart network
logger "restart network finish"

logger "set dns start"
/bin/echo -n > /etc/resolv.conf
[ ! -z $dns1 ] && /bin/echo "nameserver $dns1" >> /etc/resolv.conf
[ ! -z $dns2 ] && /bin/echo "nameserver $dns2" >> /etc/resolv.conf

logger "mq handler start"
/bin/ps -aux | /bin/grep mq_handler |  /bin/grep python |/bin/grep -v grep
result=$?
if [ $result -ne 0 ]; then
    /bin/python /home/httpd/ceph-rolling-update-cgi/mq_handler.py &
fi

logger "check qcvm ip start"
if [ "x$0" = "x/root/qcvm_ipconfig_s.sh" ];then
    /root/check_qcvm_IP.sh configure_ip_only >> ${QCVM_LOG_FILE}
else
    /root/check_qcvm_IP.sh do_it_now >> ${QCVM_LOG_FILE} &
fi
logger "check qcvm ip finish"