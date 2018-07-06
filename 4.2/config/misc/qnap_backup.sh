#!/bin/sh

PREFIX="/"
TEMP="`pwd`/temp"
OUT_FILE="`pwd`/engine.tar"
CURRENT_PATH=`pwd`
IN_FILE=""
OUT_FILE=""
function get_pass() {
	OIFS=$IFS
	IFS='='
	READFILE=/etc/ovirt-engine/engine.conf.d/10-setup-database.conf
	str=""
	substr=""
	while read line; do
		read -ra array <<< "$line"
		if [ "${array[0]}" == "ENGINE_DB_PASSWORD" ]; then
			str=${array[1]}
			len=${#str}
			substr=${str:1:len-2}
		fi
	done < $READFILE
	IFS=$OIFS
	echo "${substr}"
}

function check_service_alive(){
	PROCESS_NUM=$(ps -ef | grep "$1" | grep -v "grep" | wc -l)
	echo "${PROCESS_NUM}"
}

function update_database() {
	#cd /var/lib/pgsql
	sudo -u postgres psql -c "DROP DATABASE engine;"
	sleep 2 
	sudo -u postgres psql -c "create database engine owner engine template template0 encoding 'UTF8' lc_collate 'en_US.UTF-8' lc_ctype 'en_US.UTF-8';"
	sleep 2 
	sudo -u postgres psql engine < "${TEMP}/engine.pg"
	sleep 2

	cd ${CURRENT_PATH}
}

function restore_mysql_cinder()
{
	sudo /usr/bin/mysqladmin -f -uroot -pcephadm drop cinder
	sudo /usr/bin/mysql --user=root -pcephadm < "${TEMP}/cinder.sql"
}

function update_config() {
	mkdir ${TEMP}
	cd ${CURRENT_PATH}
	tar -xvf ${IN_FILE} 
	yes|cp -rf ${TEMP}/ovirt-engine /etc/
	yes|cp -rf /etc/pki/ovirt-engine/certs/apache.cer /etc/pki/ovirt-engine/certs/apache.cer
	yes|cp -rf /etc/pki/ovirt-engine/apache-ca.pem /etc/pki/ovirt-engine/
	yes|cp -rf /etc/pki/ovirt-engine/keys/apache.key.nopass /etc/pki/ovirt-engine/keys
	yes|cp -rf /etc/pki/ovirt-engine/certs/engine.cer /etc/pki/ovirt-engine/certs/
	yes|cp -rf /etc/pki/ovirt-engine/keys/engine.p12 /etc/pki/ovirt-engine/keys/
	yes|cp -rf /etc/pki/ovirt-engine/keys/engine_id_rsa /etc/pki/ovirt-engine/keys/
}

function restore_nas_ini() {
	yes|cp -rf ${TEMP}/nas_ceph_info.ini /home/httpd/ceph-rolling-update-cgi/
	yes|cp -rf ${TEMP}/nasInfo.conf /home/httpd/qcs_ceph_deploy_cgi/config/
}

function restore_nas_ipconfig() {
	yes|cp -rf ${TEMP}/ifcfg-eth0 /etc/sysconfig/network-scripts/
	yes|cp -rf ${TEMP}/network /etc/sysconfig/network
	systemctl restart network
    sleep 1
	yes|cp -rf ${TEMP}/resolv.conf /etc/
	/root/check_qcvm_IP.sh  do_it_now
}

function update_db_pass() {
	cd /var/lib/pgsql
	passwd=`get_pass`
	sudo -u postgres psql -c "alter role engine ENCRYPTED PASSWORD '${passwd}';"
	cd ${CURRENT_PATH}
}

function exec_cmd() {
	`$1`
}

function start_services2() {
	systemctl start ovirt-engine
	systemctl start ovirt-fence-kdump-listener
	systemctl start ovirt-websocket-proxy
	#systemctl start ovirt-engine-dwhd.service
}

function stop_services2() {
	systemctl stop ovirt-engine
	systemctl stop ovirt-fence-kdump-listener
	systemctl stop ovirt-websocket-proxy
	systemctl stop ovirt-engine-dwhd.service
}

function start_services() {
	declare -a process[3]
	declare -i alive=0
	declare -i retry=5	
	process[0]="/usr/share/ovirt-engine/services/ovirt-websocket-proxy/ovirt-websocket-proxy.py"
	process[1]="/usr/share/ovirt-engine/services/ovirt-fence-kdump-listener/ovirt-fence-kdump-listener.py"
	process[2]="/usr/share/ovirt-engine/services/ovirt-engine/ovirt-engine.py"
	while [ $alive -lt ${#process[@]} ] && [ $retry -gt 0 ];
	do
		for((i=0; i<${#process[@]}; i++))
		do
			val=`check_service_alive "${process[$i]} start"`
			if [ $val -eq 0 ]; then
				exec_cmd "${process[$i]} start" &
				echo "${process[$i]} still dead..."
				sleep 2 
			else
				alive=$alive+1
				echo "${process[$i]} alive!!"
			fi
		done
		if [ $alive -lt ${#process[@]} ]; then
			if [ $retry -eq 0 ]; then
				echo "Retry exhausts for starting services"
			else
				echo "Retry starting services"
			fi
			sleep 3
			retry=$retry-1
		fi
	done
}

function stop_services() {
	declare -a process[4]
	process[0]="ovirt-engine.py start"
	process[1]="ovirt-websocket-proxy.py start"
	process[2]="ovirt-fence-kdump-listener.py start"
	process[3]="ovirt-engine -server"
	declare -i alive=${#process[@]}
	declare -i retry=5	
	while [ $alive -gt 0 ] && [ $retry -gt 0 ];
	do
		alive=${#process[@]}
		for((i=0; i<${#process[@]}; i++))
		do
			val=`check_service_alive ${process[$i]}`
			proc_name=${process[$i]}
			kill -9 `ps ax|grep "${process[$i]}"|grep -v grep|awk '{print $1}'`
			if [ $val -eq 0 ]; then
				alive=$alive-1
				echo "${process[$i]} dead"
			else 
				echo "${process[$i]} still alive..."
			fi
		done
		
		if [ $alive -gt 0 ]; then
			if [ $retry -eq 0 ]; then
				echo "Retry exhausts for stopping services"
			else
				echo "Retry stopping services"
			fi
			sleep 3
			retry=$retry-1
		fi
	done
}

while [[ $# -gt 1 ]]
do
	key="$1"
	case $key in
		-m|--mode)
			MODE="$2"
			shift
			;;
		-f|--file)
			IN_FILE="$2"
			shift
			;;
		-p|--prefix)
			PREFIX="$2"
			shift
			;;
		-o|--output)
			OUT_FILE="$2"
			shift
			;;
		*)
			;;
	esac
	shift
done

case "$MODE" in
	"backup")
		echo "====== Start Backup ======"
		timestamp=`date +%Y%m%d-%H-%M-%S`
		if [ "$OUT_FILE" = "" ];then 
			OUT_FILE="engine-${timestamp}.tar"
		fi
		echo "  Prefix=${PREFIX}"
		echo "  BackupFile=${OUT_FILE}"
		
		mkdir -p ${TEMP}
		cd /var/lib/pgsql
		sudo -u postgres pg_dump engine > ${TEMP}/engine.pg
		#Task 26651 backup/restore cinder related configuration in MySQL
		sudo mysqldump --user=root -pcephadm --databases cinder > ${TEMP}/cinder.sql
		cd ${TEMP}
		yes|cp -rf /etc/ovirt-engine ./ 
		cp /home/httpd/ceph-rolling-update-cgi/nas_ceph_info.ini ./
		cp /etc/sysconfig/network-scripts/ifcfg-eth0 ./
		cp /etc/sysconfig/network ./
		cp /etc/resolv.conf ./
		cp /home/httpd/qcs_ceph_deploy_cgi/config/nasInfo.conf ./
		cd ${CURRENT_PATH}
		tar -cvf ${OUT_FILE} ./temp 
		rm -rf ${TEMP}
		echo "====== End Backup ======"
	;;
	"restore")
		if [ ! -f "$IN_FILE" ]; then
			echo "restore file is not exist" 
			exit
		fi
		echo 0 > /tmp/restore_percent
		echo "====== Start Restore ======"
		echo "  Prefix=${PREFIX}"
		echo "  RestoreFile=${IN_FILE}"

		echo "  --- stop ovirt services"
		stop_services2
		echo 5 > /tmp/restore_percent
        
		echo "  --- stop httpd service"
		systemctl stop httpd
		echo 10 > /tmp/restore_percent
        
		echo "  --- restart postgresql service"
		systemctl restart postgresql
		sleep 3
		echo 15 > /tmp/restore_percent

		echo "  --- update config"
		update_config
		echo 20 > /tmp/restore_percent

		echo "  --- update mysql cinder database"
		restore_mysql_cinder
		echo 30 > /tmp/restore_percent
        
		echo "  --- update database"
		update_database
		echo 65 > /tmp/restore_percent
        
		echo "  --- update db pass"
		update_db_pass
		echo 70 > /tmp/restore_percent
        
		echo "  --- restore ini file" 
		restore_nas_ini
		echo 75 > /tmp/restore_percent
        
		echo "  --- start httpd"
		systemctl start httpd
		sleep 3
		echo 80 > /tmp/restore_percent
        
		echo "  --- start ovirt service"
		start_services2
		sleep 3
		echo 90 > /tmp/restore_percent
        
		echo "  --- reconfig ipconfig"
		restore_nas_ipconfig
		echo 100 > /tmp/restore_percent
        
		echo "====== End Restore ======"
		/bin/rm -rf ${TEMP}
		;;
	"stop")
		stop_services2
	;;
	"start")
		start_services2
	;;
	*)
	echo "Invalid Arugment"
	;;
esac