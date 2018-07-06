gen_ovirtshellrc()
{
    rm /root/.ovirtshellrc
    echo "[qcvm]" > /root/.ovirtshellrc
    echo "source = init_ovirte.sh" >> /root/.ovirtshellrc
    echo "[cli]" >> /root/.ovirtshellrc
    echo "autoconnect = True" >> /root/.ovirtshellrc
    echo "autopage = True" >> /root/.ovirtshellrc
    echo "[ovirt-shell]" >> /root/.ovirtshellrc
    echo "username = admin@internal" >> /root/.ovirtshellrc
    echo "renew_session = False" >> /root/.ovirtshellrc
    echo "timeout = None" >> /root/.ovirtshellrc
    echo "extended_prompt = False" >> /root/.ovirtshellrc
    echo "url = https://qcvm.local:$HTTPS_PORT/ovirt-engine/api" >> /root/.ovirtshellrc
    echo "insecure = False" >> /root/.ovirtshellrc
    echo "kerberos = False" >> /root/.ovirtshellrc
    echo "filter = False" >> /root/.ovirtshellrc
    echo "session_timeout = None" >> /root/.ovirtshellrc
    echo "ca_file = /etc/pki/ovirt-engine/ca.pem" >> /root/.ovirtshellrc
    echo "dont_validate_cert_chain = False" >> /root/.ovirtshellrc
    echo "key_file = None" >> /root/.ovirtshellrc
    echo "password = admin" >> /root/.ovirtshellrc
    echo "cert_file = /etc/pki/ovirt-engine/certs/engine.cer" >> /root/.ovirtshellrc
}

check_engine_status()
{
    c=0
    ENGINE_STATE=$(ovirt-shell -c -E "exit" 2>&1 | grep "(connected)")
    while [ -z "${ENGINE_STATE}" ]; do
        sleep 5
        ENGINE_STATE=$(ovirt-shell -c -E "exit" 2>&1 | grep "(connected)")
        c=$[$c+1]

        if [ $c -gt 120 ];then
            /bin/echo "[$(date)] init_ovirt fail --> ENGINE: engine can not be connected. Try Count: ${c}"  >> ${LOG_FILE}
            exit 1
        fi
    done
    /bin/echo "[$(date)] ENGINE: is ready. Try Count: ${c}"  >> ${LOG_FILE}
    /bin/echo "$ENGINE_STATE" >> ${LOG_FILE}
    /bin/echo "===> system info dump ===" >> ${LOG_FILE}
    grep url /root/.ovirtshellrc 2>&1 >> ${LOG_FILE}
    grep cert_file /root/.ovirtshellrc 2>&1 >> ${LOG_FILE}
    ping -c 1 qcvm.local 2>&1 >> ${LOG_FILE}
    netstat -ntpl | grep 443 2>&1 >> ${LOG_FILE}
    /bin/echo "=== system info dump <===" >> ${LOG_FILE}
}

add_host()
{
    HOST_NAME=$1
    HOST_IP=$2
    SSH_USER=$3
	LOG_FILE=$4

    LOG=$(/usr/bin/ovirt-shell -c -E "add host --name ${HOST_NAME} --address ${HOST_IP} --ssh-user-user_name ${SSH_USER} --ssh-authentication_method publickey --cluster-name Default" 2>&1)
    c=0
    STATE=$(/bin/echo ${LOG} | grep "Failed connect")
    while [ ! -z "${STATE}" ]; do
        sleep 5
        LOG=$(/usr/bin/ovirt-shell -c -E "add host --name ${HOST_NAME} --address ${HOST_IP} --ssh-user-user_name ${SSH_USER} --ssh-authentication_method publickey --cluster-name Default" 2>&1)
        STATE=$(/bin/echo ${LOG} | grep "Failed connect")
        c=$[$c+1]

        if [ $c -gt 120 ];then
            /bin/echo "[$(date)] init_ovirt fail --> HOST: host can not be added due to service not ready. Try Count: ${c}"  >> ${LOG_FILE}
            exit 1
        fi
    done
    echo "host adding try count: ${c}" >> ${LOG_FILE}
    echo "${LOG}" >> ${LOG_FILE}
}

if [ ! -d "/root/ovirte_log" ]; then
    mkdir -p /root/ovirte_log
fi

LOG_FILE=/root/ovirte_log/init_ovirte.log

/bin/echo "[$(date)] [init_ovirte]"  >> ${LOG_FILE}
if [ $# -ne 2 ]; then
    echo "Usage: init_ovirte.sh <host_ip> <hostname>"
    /bin/echo "[$(date)] Usage: init_ovirte.sh <host_ip> <hostname>" >> ${LOG_FILE}
    /bin/echo "$@" >> ${LOG_FILE}
    exit
fi

HOST_IP=$1
HOST_NAME=$2
VM_IP=$(ifconfig | grep -A 1 'eth0' | tail -1 | awk '{print$2}')

SSH_USER="admin"

if [ -z "${HOST_NAME}" ]; then
    HOST_NAME="auto_host"
else
    HOST_NAME="auto_${HOST_NAME}"
fi

LOG_FILE=/root/ovirte_log/init_ovirte_${HOST_NAME}.log
/bin/echo "[$(date)] HOST_IP: ${HOST_IP}" > ${LOG_FILE}
/bin/echo "[$(date)] HOST_NAME: ${HOST_NAME}" >> ${LOG_FILE}
/bin/echo "[$(date)] VM_IP: ${VM_IP}" >> ${LOG_FILE}

gen_ovirtshellrc

#waiting for engine ready
check_engine_status
FOUND_HOST=0
for h in $(/usr/bin/ovirt-shell -c -E "list hosts" | grep name | awk '{ print $3 }')
do
     ADDR=$(/usr/bin/ovirt-shell -c -E "show host ${h}" | grep address | awk '{ print $3 }')
     if [ x"${ADDR}" == x"$HOST_IP" ]; then
         HOST_NAME=${h}
         /bin/echo "[$(date)] HOST: ${h} with address: ${ADDR} already exists"  >> ${LOG_FILE}
         FOUND_HOST=1
         break
     fi
done

HOST_STATE=""
c=0
if [ ${FOUND_HOST} == 0 ]; then
    check_engine_status

    #add external network
    /usr/bin/ovirt-shell -c -E "add openstacknetworkprovider --name neutron_network --plugin_type open_vswitch  --url http://${VM_IP}:9696 --requires_authentication 1 --username admin --password admin --tenant_name admin --authentication_url http://${VM_IP}:35357/v2.0 --agent_configuration-broker_type rabbit_mq --agent_configuration-address ${VM_IP} --agent_configuration-port 5672 --agent_configuration-username cephadm --agent_configuration-password rabbit" > /root/${HOST_NAME}.log 2>&1
    sleep 5

    add_host ${HOST_NAME} ${HOST_IP} ${SSH_USER} ${LOG_FILE} >> /root/ovirte_log/${HOST_NAME}.log 2>&1
    HOST_STATE=$(/usr/bin/ovirt-shell -c -E "show host ${HOST_NAME}"  | grep ^status-state | grep up)
    while [ -z "${HOST_STATE}" ]; do
        sleep 5
        HOST_STATE=$(/usr/bin/ovirt-shell -c -E "show host ${HOST_NAME}"  | grep ^status-state | grep up)
        c=$[$c+1]

        if [ $c -gt 120 ];then
            /bin/echo "[$(date)] init_ovirt fail --> HOST: ${HOST_NAME} can not be UP. Try Count: ${c}"  >> ${LOG_FILE}
            exit 1
        fi
    done
else
    HOST_STATE=$(/usr/bin/ovirt-shell -c -E "show host ${HOST_NAME}"  | grep ^status-state | grep up)
    if [ -z "${HOST_STATE}" ]; then
            /bin/echo "[$(date)] init_ovirt fail --> HOST: ${HOST_NAME} exists but is not UP. Try Count: ${c}"  >> ${LOG_FILE}
            exit 1
    fi
fi
/bin/echo "[$(date)] ${HOST_NAME} is ${HOST_STATE}. Try Count: ${c}" >> ${LOG_FILE}

/bin/touch /root/init_ovirtE.flag
/bin/echo "[$(date)] init_ovirte successfully"  >> ${LOG_FILE}