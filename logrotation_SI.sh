#!/bin/bash

###
# BD, listener and Audit log rotation
#
# usage: logrotation.sh <sid> (<keepdays_trace>)
# keepdays - default 15 days
#
# Notes: /etc/oratab must contain correct vars
###


#Set env vars
if [ $1 ]
then
	ORACOUNT=`grep -i "$1:" /etc/oratab | wc -l`
	if [ $ORACOUNT -eq 1 ]
	then
		ORAENTRY=`grep -i "$1:" /etc/oratab`
		export ORACLE_SID=`echo $ORAENTRY | awk -F: '{print $1}'`
		export ORACLE_HOME=`echo $ORAENTRY | awk -F: '{print $2}'`		
		export PATH=$ORACLE_HOME/bin:$PATH
		echo "VAR: ORACLE_SID: ${ORACLE_SID}"
		echo "VAR: ORACLE_HOME: ${ORACLE_HOME}"
	else
		echo "ERR: $1 not unique or not found in /etc/oratab"
		exit 101
	fi
else
	echo "Usage: logrotation.sh <sid> (<keepdays>)"
	exit 100
fi

# Set keep days
if [ $2 ]
then
	PURGE_DAYS=${2}
	let PURGE_TIME=${PURGE_DAYS}*60*24
else
	PURGE_TIME=21600 #15 days
	PURGE_DAYS=15
fi
echo "VAR: KEEPTIME: ${PURGE_DAYS} (days)"
echo ""

# Vars
ORACLE_USER="oracle"
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

# Check SID
if [ `ps -ef | grep -w ora_pmon_${ORACLE_SID} | grep -v grep | wc -l` -eq 0 ]
then
	echo "$ORACLE_SID is not running here"
	exit 97
fi

# Start purging
START_DATE="$(/bin/date)"
echo "INF: Initializing Purge $START_DATE"
echo ""

adr_base=`$ORACLE_HOME/bin/sqlplus -SL "/as sysdba" <<EOF
set echo off ver off feedb off head off pages 0
select value from v\\$diag_info where name='ADR Base';
exit;
EOF
`

$ORACLE_HOME/bin/adrci exec="set base $adr_base;show homes"| grep -v : | while read LINE
do
	echo "INF: purging home $LINE"
	sleep 5
	echo " purging ALERT"
	$ORACLE_HOME/bin/adrci exec="set base $adr_base;set homepath $LINE;purge -age ${PURGE_TIME} -type ALERT"
	echo " purging INCIDENT"
	$ORACLE_HOME/bin/adrci exec="set base $adr_base;set homepath $LINE;purge -age ${PURGE_TIME} -type INCIDENT"
	echo " purging TRACE"
	$ORACLE_HOME/bin/adrci exec="set base $adr_base;set homepath $LINE;purge -age ${PURGE_TIME} -type TRACE"
	echo " purging CDUMP"
	$ORACLE_HOME/bin/adrci exec="set base $adr_base;set homepath $LINE;purge -age ${PURGE_TIME} -type CDUMP"
	echo " purging HM"
	$ORACLE_HOME/bin/adrci exec="set base $adr_base;set homepath $LINE;purge -age ${PURGE_TIME} -type HM"
	echo ""
done

audit_trace=`$ORACLE_HOME/bin/sqlplus -SL "/as sysdba" <<EOF
set echo off ver off feedb off head off pages 0
select value from v\\$parameter where name='audit_file_dest';
exit;
EOF
`

echo "INF: Purge Audit files at ${audit_trace} keep time 60 days"
echo ""
sleep 5

find $audit_trace -name "*.aud" -mtime +60 -exec rm {} \;

diag_trace=`$ORACLE_HOME/bin/sqlplus -SL "/as sysdba" <<EOF
set echo off ver off feedb off head off pages 0
select value from v\\$diag_info where name='Diag Trace';
exit;
EOF
`

#Alert Log
alert_log=alert_$ORACLE_SID.log

echo "INF: Rotate alertlog of ${ORACLE_SID} database at ${alert_log} keep time 60 days"
echo ""
sleep 5

mv ${diag_trace}/${alert_log} ${diag_trace}/${alert_log}.${data}
touch ${diag_trace}/${alert_log}
gzip -f ${diag_trace}/${alert_log}.${data}
find ${diag_trace} -name "${alert_log}.*.gz" -mtime +60 -exec rm {} \;

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
