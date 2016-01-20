#!/bin/sh

# set -x

# Program name: nmon_manage.sh
# Purpose - nmon simple script designed to call associated libs and manage nmon data
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".
# Date - Jan 2016

# Jan 2015, Guilhem Marchand: Initial version

# Version 1.0.0

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

# hostname
HOST=`hostname`

NMON_BIN=$1
NMON_HOME=$2

if [ -z "${NMON_BIN}" ]; then
	echo "`date`, ${HOST} ERROR, The NMON_BIN directory that contains the binaries full path must be given in first
	 argument of this script"
	exit 1
fi

if ! [ -d ${NMON_HOME} ]; then
    echo "`date`, ${HOST} ERROR, The NMON_BIN directory full path provided in second argument could not be
    found (we tried: ${NMON_BIN}"
	exit 1
fi

if [ -z "${NMON_HOME}" ]; then
	echo "`date`, ${HOST} ERROR, The NMON_HOME directory for data generation full path must be given in second
	argument of this script"
	exit 1
fi

if ! [ -d ${NMON_HOME}/var/nmon_repository ]; then
    echo "`date`, ${HOST} ERROR, Could not find expected directory structure, please first start the nmon_helper.sh
     script"
	exit 1
fi

for nmon_file in `find ${NMON_HOME}/var/nmon_repository -name "*.nmon" -type f -print`; do

    cat $nmon_file | python ${NMON_BIN}/bin/nmon2kv.py --mode realtime --nmon_home ${NMON_HOME}

done

exit 0

