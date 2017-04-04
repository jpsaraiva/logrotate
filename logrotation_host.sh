#!/bin/bash

###
# BDs, listener and Audit log rotation
#
# usage: logrotation.sh
#
# Note: This scripts was made for a specific setup, will not be reproducible without modifications on other machines
###

export ORACLE_HOME=/products/grid/11204
export ORACLE_BASE=/products/oracle
export PATH=$ORACLE_HOME/bin:$PATH

# Vars
ORACLE_USER="oracle"
PURGE_TIME=43200 #30 Days
data=`date "+%Y%m%d"`

# Check USER
USER=`whoami`

if [ "$USER" != "$ORACLE_USER" ]
then
echo "ERR: Script must run as $ORACLE_USER."
exit 99
fi

# Check ORACLE_HOME
if [ -z ${ORACLE_HOME} ]
then
	echo "ERR: ORACLE_HOME must be set."
	exit 98
fi

# Check ORACLE_BASE
if [ -z ${ORACLE_BASE} ]
then
	echo "ERR: ORACLE_BASE must be set."
	exit 98
fi

# Start purging
START_DATE="$(/bin/date)"
echo "INF: Initializing Purge $START_DATE"
echo ""

$ORACLE_HOME/bin/adrci exec="set base /products/oracle; show homes"| grep -v : | while read LINE
do
	echo "INF: purging home $LINE"
	sleep 5
	echo " purging ALERT"
	$ORACLE_HOME/bin/adrci exec="set base /products/oracle; set homepath $LINE;purge -age ${PURGE_TIME} -type ALERT"
	echo " purging INCIDENT"
	$ORACLE_HOME/bin/adrci exec="set base /products/oracle; set homepath $LINE;purge -age ${PURGE_TIME} -type INCIDENT"
	echo " purging TRACE"
	$ORACLE_HOME/bin/adrci exec="set base /products/oracle; set homepath $LINE;purge -age ${PURGE_TIME} -type TRACE"
	echo " purging CDUMP"
	$ORACLE_HOME/bin/adrci exec="set base /products/oracle; set homepath $LINE;purge -age ${PURGE_TIME} -type CDUMP"
	echo " purging HM"
	$ORACLE_HOME/bin/adrci exec="set base /products/oracle; set homepath $LINE;purge -age ${PURGE_TIME} -type HM"
	echo " rotating LOG"
	echo ""
done

$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; show homes"| grep -v : | while read LINE
do
	echo "INF: purging home $LINE"
	sleep 5
	echo " purging ALERT"
	$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; set homepath $LINE;purge -age ${PURGE_TIME} -type ALERT"
	echo " purging INCIDENT"
	$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; set homepath $LINE;purge -age ${PURGE_TIME} -type INCIDENT"
	echo " purging TRACE"
	$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; set homepath $LINE;purge -age ${PURGE_TIME} -type TRACE"
	echo " purging CDUMP"
	$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; set homepath $LINE;purge -age ${PURGE_TIME} -type CDUMP"
	echo " purging HM"
	$ORACLE_HOME/bin/adrci exec="set base /products/grid/11204/log; set homepath $LINE;purge -age ${PURGE_TIME} -type HM"
	echo " rotating LOG"
	echo ""
done

echo "INF: Purge Audit files at ${ORACLE_BASE}/admin keep time 30 days"
echo ""
sleep 5

find ${ORACLE_BASE}/admin/ -name "*.aud" -type f -mtime +30 -exec rm {} \;

#Alert Log
for osid in `ps -edf | grep -i ora_pmon | egrep -v "grep|sed" | awk '{print $8}' | sed 's/ora_pmon_//'`
do
echo "INF: Rotate alert log of ${osid} database"
ALERT_LOG="${ORACLE_BASE}/diag/rdbms/`echo ${osid%[0-9]} |tr [:upper:] [:lower:]`/${osid}/trace/alert_${osid}.log"
mv ${ALERT_LOG} ${ALERT_LOG}.${data}
touch ${ALERT_LOG}
gzip -f ${ALERT_LOG}.${data}
done;

#Purge Alert Log gz's older than 60 days
find ${ORACLE_BASE}/diag/rdbms/ -name "alert_*.*.gz" -mtime +60 -exec rm {} \;

#Purge uncompressed alert logs after 90 days
find ${ORACLE_BASE}/diag/rdbms/ -name "alert_*.log.*" -mtime +90 -exec rm {} \;

#listener
for listener in `ps -ef | grep -i tnslsnr | grep ${ORACLE_USER} | egrep -v grep | awk '{print $9}'`
do
TRC_DIR=`lsnrctl <<!
set current_listener ${listener}
show trc_directory
!
`
TRC_DIR=`echo ${TRC_DIR} | grep -oP '(?<=set to ).*(?= The)'`
listener_log=`echo ${listener}.log | tr '[:upper:]' '[:lower:]'`

if [ -f ${TRC_DIR}/${listener_log} ]
then
	echo "INF: Rotate log for listener ${listener} at ${listener_log} keep time 60 days"
	echo ""
	sleep 5
	
	mv ${TRC_DIR}/${listener_log} ${TRC_DIR}/${listener_log}.${data}
	touch ${TRC_DIR}/${listener_log}
	gzip -f ${TRC_DIR}/${listener_log}.${data}
	find ${TRC_DIR} -name "${listener_log}.*.gz" -mtime +60 -exec rm {} \;
	
else 
	echo "INF: File ${listener_log} for listener ${listener} exists does not exists"
fi
done;

# End of purge
END_DATE="$(/bin/date)"
echo "INF: Purge ended $END_DATE"
exit
