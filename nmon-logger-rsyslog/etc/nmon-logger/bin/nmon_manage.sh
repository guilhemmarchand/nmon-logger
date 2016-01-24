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

userarg1=$1
userarg2=$2

case ${userarg1} in
"")
	echo "`date`, ${HOST} ERROR, the binary home directory for nmon-logger must be provided in first argument. (default: /etc/nmon-logger)"
	exit 1
;;
esac

case ${userarg2} in
"")
        echo "`date`, ${HOST} ERROR, the log home directory for nmon-logger must be provided in second argument. (default: /var/log/nmon-logger)"
        exit 1
;;
esac

NMON_BIN=${userarg1}
NMON_VAR=${userarg2}

if ! [ -d ${NMON_BIN} ]; then
    echo "`date`, ${HOST} ERROR, The NMON_BIN directory full path provided in second argument could not be
    found (we tried: ${NMON_BIN}"
	exit 1
fi

if ! [ -d ${NMON_VAR}/var/nmon_repository ]; then
    echo "`date`, ${HOST} ERROR, Could not find expected directory structure, please first start the nmon_helper.sh
     script"
	exit 1
fi

for nmon_file in `find ${NMON_VAR}/var/nmon_repository -name "*.nmon" -type f -print`; do

    cat $nmon_file | ${NMON_BIN}/bin/nmon2kv.sh ${NMON_BIN} ${NMON_VAR}

done

exit 0

