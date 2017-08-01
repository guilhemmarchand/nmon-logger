#!/bin/sh

# set -x

# Program name: fifo_consumer.sh
# Purpose - consume data produced by the fifo readers
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".
# Date - June 2014

# - 2017/06/05, V1.0.2: Guilhem Marchand:
#                                          - Mirror update of the TA-nmon

# Version 1.0.2

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

# hostname
HOST=`hostname`

# Which type of OS are we running
UNAME=`uname`

# tmp file
temp_file="/tmp/fifo_consumer.sh.$$"

# APP path discovery
APP="/etc/nmon-logger"

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

# default values relevant for our context
nmon2csv_options="--mode fifo"

# source default nmon.conf
if [ -f $APP/default/nmon.conf ]; then
	. $APP/default/nmon.conf
fi

# source local nmon.conf, if any

# Search for a local nmon.conf file located in $SPLUNK_HOME/etc/apps/TA-nmon/local
if [ -f $APP/local/nmon.conf ]; then
	. $APP/local/nmon.conf
fi

# On a per server basis, you can also set in /etc/nmon.conf
if [ -f /etc/nmon.conf ]; then
	. /etc/nmon.conf
fi

############################################
# functions
############################################

# consume function
consume_data () {

# fifo name (valid choices are: fifo1 | fifo2)
FIFO=$1

# consume fifo

# realtime
nmon_config=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_config.dat
nmon_header=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_header.dat
nmon_timestamp=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_timestamp.dat
nmon_data=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_data.dat
nmon_data_tmp=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_data_tmp.dat
nmon_external=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_external.dat
nmon_external_header=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_external_header.dat

# rotated
nmon_config_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_config.dat.rotated
nmon_header_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_header.dat.rotated
nmon_timestamp_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_timestamp.dat.rotated
nmon_data_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_data.dat.rotated
nmon_external_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_external.dat.rotated
nmon_external_header_rotated=/var/log/nmon-logger/var/nmon_repository/$FIFO/nmon_external_header.dat.rotated

# manage rotated data if existing, prevent any data loss

# all files must be existing to be managed
if [ -s $nmon_config_rotated ] && [ -s $nmon_header_rotated ] && [ -s $nmon_data_rotated ]; then

    # Manager headers
    unset nmon_header_files
    if [ -f $nmon_external_header_rotated ]; then
        nmon_header_files="$nmon_header_rotated $nmon_external_header_rotated"
    else
        nmon_header_files="$nmon_header_rotated"
    fi

    # Ensure the first line of nmon_data starts by the relevant timestamp, if not add it
    head -1 $nmon_data_rotated | grep 'ZZZZ,T' >/dev/null
    if [ $? -ne 0 ]; then
        # check timestamp dat exists before processing
        # there is no else possible, if the the timestamp data file does not exist, there is nothing we can do
        # and the parser will raise an error
        if [ -f $nmon_timestamp_rotated ]; then
            tail -1 $nmon_timestamp_rotated >$temp_file
            cat $nmon_config_rotated $nmon_header_files $temp_file $nmon_data_rotated $nmon_external_rotated | /etc/nmon-logger/bin/nmon2kv.sh $nmon2csv_options
        fi
    else
        cat $nmon_config_rotated $nmon_header_files $nmon_data_rotated $nmon_external_rotated | /etc/nmon-logger/bin/nmon2kv.sh $nmon2csv_options
    fi

    # remove rotated
    rm -f /var/log/nmon-logger/var/nmon_repository/$FIFO/*.dat.rotated

    # header var
    unset nmon_header_files

fi

# Manage realtime files

# all files must be existing to be managed
if [ -s $nmon_config ] && [ -s $nmon_header ] && [ -s $nmon_data ]; then

    # get data mtime
    case $INTERPRETER in
    "perl")
        perl -e "\$mtime=(stat(\"$nmon_data\"))[9]; \$cur_time=time();  print \$cur_time - \$mtime;" >$temp_file
        nmon_data_mtime=`cat $temp_file`
        ;;

    "python")
        python -c "import os; import time; now = time.strftime(\"%s\"); print(int(int(now)-(os.path.getmtime('$nmon_data'))))" >$temp_file
        nmon_data_mtime=`cat $temp_file`
        ;;
    esac

    # file should have last mtime of mini 5 sec

    while [ $nmon_data_mtime -lt 5 ];
    do

        sleep 1

        # get data mtime
        case $INTERPRETER in
        "perl")
            perl -e "\$mtime=(stat(\"$nmon_data\"))[9]; \$cur_time=time();  print \$cur_time - \$mtime;" >$temp_file
            nmon_data_mtime=`cat $temp_file`
            ;;

        "python")
            python -c "import os; import time; now = time.strftime(\"%s\"); print(int(int(now)-(os.path.getmtime('$nmon_data'))))" >$temp_file
            nmon_data_mtime=`cat $temp_file`
            ;;
        esac


    done

    # copy content
    cat $nmon_data > $nmon_data_tmp

    # nmon external data
    if [ -f $nmon_external ]; then
        cat $nmon_external >> $nmon_data_tmp
    fi

    # empty the nmon_data file & external
    > $nmon_data
    > $nmon_external

    # Manager headers
    unset nmon_header_files
    if [ -f $nmon_external_header ]; then
        nmon_header_files="$nmon_header $nmon_external_header"
    else
        nmon_header_files="$nmon_header"
    fi

    # Ensure the first line of nmon_data starts by the relevant timestamp, if not add it
    head -1 $nmon_data_tmp | grep 'ZZZZ,T' >/dev/null
    if [ $? -ne 0 ]; then
        tail -1 $nmon_timestamp >$temp_file
        cat $nmon_config $nmon_header_files $temp_file $nmon_data_tmp | /etc/nmon-logger/bin/nmon2kv.sh $nmon2csv_options
    else
        cat $nmon_config $nmon_header_files $nmon_data_tmp | /etc/nmon-logger/bin/nmon2kv.sh $nmon2csv_options
    fi

    # remove the copy
    rm -f $nmon_data_tmp

    # header var
    unset nmon_header_files

fi

}

####################################################################
#############		Main Program 			############
####################################################################

# consume fifo1
consume_data fifo1

# allow 1 sec idle
sleep 1

# consume fifo2
consume_data fifo2

# remove the temp file
if [ -f $temp_file ]; then
    rm -f $temp_file
fi

exit 0
