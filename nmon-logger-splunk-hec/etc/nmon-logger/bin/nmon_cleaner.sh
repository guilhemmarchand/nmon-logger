#!/bin/sh

# set -x

# Program name: nmon_cleaner.sh
# Compatibility: sh
# Purpose - Shell wrapper for nmon_cleaner.py / nmon_cleaner.pl
# Author - Guilhem Marchand
# Date of first publication - Jan 2016

# Releases Notes:

# - Jan 2016, V1.0.0: Guilhem Marchand, Initial version
# - 02/08/2017, V1.0.1: Guilhem Marchand, importing maintenance tasks from TA-nmon

# Version 1.0.1

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

####################################################################
#############		Main Program 			############
####################################################################

# Store the first  and second user argument as the value for nmon_home
# nmon_cleaner.pl / nmon_cleaner.py only need one argument for nmon_home which is the second argument sent to this script
userarg1=$1
userarg2=$2

# Set host
HOST=`hostname`

# format date output to strftime dd/mm/YYYY HH:MM:SS
log_date () {
    date "+%d-%m-%Y %H:%M:%S"
}

case ${userarg1} in
"")
	echo "`log_date`, ${HOST} ERROR, the binary home directory for nmon-logger must be provided in first argument. (default: /etc/nmon-logger)"
	exit 1
;;
esac

case ${userarg2} in
"")
        echo "`log_date`, ${HOST} ERROR, the log home directory for nmon-logger must be provided in second argument. (default: /var/log/nmon-logger)"
        exit 1
;;
esac

NMON_BIN=${userarg1}
NMON_VAR=${userarg2}

# source default nmon.conf
if [ -f $NMON_BIN/default/nmon.conf ]; then
	. $NMON_BIN/default/nmon.conf
fi

# source local nmon.conf, if any

# Search for a local nmon.conf file located in $SPLUNK_HOME/etc/apps/TA-nmon/local
if [ -f $NMON_BIN/local/nmon.conf ]; then
	. $NMON_BIN/local/nmon.conf
fi

# On a per server basis, you can also set in /etc/nmon.conf
if [ -f /etc/nmon.conf ]; then
	. /etc/nmon.conf
fi

# Manage FQDN option
echo $nmon2csv_options | grep '\-\-use_fqdn' >/dev/null
if [ $? -eq 0 ]; then
    HOST=`hostname -f`
else
    HOST=`hostname`
fi

#
# Interpreter choice
#

PYTHON=0
PERL=0
# Set the default interpreter
INTERPRETER="python"

# Get the version for both worlds
PYTHON=`which python >/dev/null 2>&1`
PERL=`which python >/dev/null 2>&1`

case $PYTHON in
*)
   python_subversion=`python --version 2>&1`
   case $python_subversion in
   *" 2.7"*)
    PYTHON_available="true" ;;
   *)
    PYTHON_available="false"
   esac
   ;;
0)
   PYTHON_available="false"
   ;;
esac

case $PERL in
*)
   PERL_available="true"
   ;;
0)
   PERL_available="false"
   ;;
esac

case `uname` in

# AIX priority is Perl
"AIX")
     case $PERL_available in
     "true")
           INTERPRETER="perl" ;;
     "false")
           INTERPRETER="python" ;;
 esac
;;

# Other OS, priority is Python
*)
     case $PYTHON_available in
     "true")
           INTERPRETER="python" ;;
     "false")
           INTERPRETER="perl" ;;
     esac
;;
esac

###### Maintenance tasks ######

#
# Maintenance task1
#

# Maintenance task 1: verify if we have nmon processes running over the allowed period
# This issue seems to happen sometimes specially on AIX servers

# If an nmon process has not been terminated after its grace period, the process will be killed

# get the allowed runtime in seconds for an nmon process according to the configuration
# and add a 10 minute grace period

case `uname` in

"AIX"|"Linux")

    echo "`log_date`, ${HOST} INFO, starting maintenance task 1: verify nmon processes running over expected time period"

    endtime=0

    case ${mode_fifo} in
    "1")
        endtime=`expr ${fifo_interval} \* ${fifo_snapshot}` ;;
    *)
        endtime=`expr ${interval} \* ${snapshot}` ;;
    esac

    endtime=`expr ${endtime} + 600`

    # get the list of running processes
    ps -eo user,pid,command,etime,args | grep "nmon-logger" | grep "var/log/nmon" | grep -v fifo_reader | grep -v grep >/dev/null

    if [ $? -eq 0 ]; then

        oldPidList=`ps -eo user,pid,command,etime,args | grep "nmon-logger" | grep "var/log/nmon" | grep -v fifo_reader | grep -v grep | awk '{ print $2 }'`
        for pid in $oldPidList; do

            pid_runtime=0
            # only run the process is running
            if [ -d /proc/${pid} ]; then
                # get the process runtime in seconds
                pid_runtime=`ps -p ${pid} -oetime= | tr '-' ':' | awk -F: '{ total=0; m=1; } { for (i=0; i < NF; i++) {total += $(NF-i)*m; m *= i >= 2 ? 24 : 60 }} {print total}'`
                if [ ${pid_runtime} -gt ${endtime} ]; then
                    echo "`log_date`, ${HOST} WARN, old nmon process found due to `ps -eo user,pid,command,etime,args | grep $pid | grep -v grep` killing (SIGTERM) process $pid"
                    kill $pid

                    # Allow some time for the process to end
                    sleep 5

                    # re-check the status
                    ps -p ${pid} -oetime= >/dev/null

                    if [ $? -eq 0 ]; then
                        echo "`log_date`, ${HOST} WARN, old nmon process found due to `ps -eo user,pid,command,etime,args | grep $pid | grep -v grep` failed to stop, killing (-9) process $pid"
                        kill -9 $pid
                    fi

                fi
            fi

        done

    fi

    #
    # Maintenance task2
    #
    #set -x
    # Maintenance task 2: An other case of issue we could have would be having the fifo_reader processing running without associated nmon processes
    # In such a case, no new nmon processes would be launched and the collection would stop

    echo "`log_date`, ${HOST} INFO, starting maintenance task 2: verify orphan fifo_reader processes"

    for instance in fifo1 fifo2; do

    # get the list of running processes
    ps -eo user,pid,command,etime,args | grep "nmon-logger" | grep fifo_reader | grep ${instance} >/dev/null

    if [ $? -eq 0 ]; then

        oldPidList=`ps -eo user,pid,command,etime,args | grep "nmon-logger" | grep fifo_reader | grep ${instance} | grep -v grep | awk '{ print $2 }'`

        # search for associated nmon process
        ps -eo user,pid,command,etime,args | grep "nmon-logger" | grep "var/log/nmon" | grep -v fifo_reader | grep ${instance} >/dev/null

        if [ $? -ne 0 ]; then

            # no process found, kill the reader processes
            for pid in $oldPidList; do
                    echo "`log_date`, ${HOST} WARN, orphan reader process found (no associated nmon process) due to `ps -eo user,pid,command,etime,args | grep $pid | grep -v grep` killing (SIGTERM) process $pid"
                    kill $pid

                    # Allow some time for the process to end
                    sleep 5

                    # re-check the status
                    ps -p ${pid} -oetime= >/dev/null

                    if [ $? -eq 0 ]; then
                    echo "`log_date`, ${HOST} WARN, orphan reader process (no associated nmon process) due to `ps -eo user,pid,command,etime,args | grep $pid | grep -v grep` failed to stop, killing (-9) process $pid"
                        kill -9 $pid
                    fi

            done

        fi

    fi

    done

;;

# End of per OS case
esac

###### End maintenance tasks ######

###### Start cleaner ######

case ${INTERPRETER} in

"python")
		${NMON_BIN}/bin/nmon_cleaner.py --nmon_home ${NMON_VAR} ;;

"perl")
		${NMON_BIN}/bin/nmon_cleaner.pl --nmon_home ${NMON_VAR} ;;

esac

exit 0
