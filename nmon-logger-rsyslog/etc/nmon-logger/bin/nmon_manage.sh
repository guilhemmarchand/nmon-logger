#!/bin/sh

# set -x

# Program name: nmon_manage.sh
# Purpose - nmon simple script designed to call associated libs and manage nmon data
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".
# Date - Jan 2016

# Jan 2015, Guilhem Marchand: Initial version
# 2016/07/17, Guilhem Marchand: Change expected structure message log level to WARN
# 2016/08/02, Guilhem Marchand: Improve identification of mtime (Perl / Python)


# Version 1.0.2
#

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

if ! [ -d ${NMON_VAR} ]; then
    mkdir ${NMON_VAR}
else
    # Remove any existing temp files
    rm -f ${NMON_VAR}/nmon_manage.sh.tmp.*
fi

if ! [ -d ${NMON_BIN} ]; then
    echo "`date`, ${HOST} ERROR, The NMON_BIN directory full path provided in second argument could not be
    found (we tried: ${NMON_BIN}"
	exit 1
fi

# Only run if the nmon_repository directory were found, if it does not exist, this is probably too early to run

if [ -d ${NMON_VAR}/var/nmon_repository ]; then

    for nmon_file in `find ${NMON_VAR}/var/nmon_repository -name "*.nmon" -type f -print`; do

        # Verify Perl availability (Perl will be more commonly available than Python)
        PERL=`which perl >/dev/null 2>&1`

        if [ $? -eq 0 ]; then

            # Use perl to get file age in seconds (perl will be portable to every system)
            perl -e "\$mtime=(stat(\"$nmon_file\"))[9]; \$cur_time=time();  print \$cur_time - \$mtime;" > ${NMON_VAR}/nmon_manage.sh.tmp.$$

        else

            # Use Python to get PID file age in seconds
            python -c "import os; import time; now = time.strftime(\"%s\"); print(int(int(now)-(os.path.getmtime('$nmon_file'))))" > ${NMON_VAR}/nmon_manage.sh.tmp.$$

        fi

        nmon_age=`cat ${NMON_VAR}/nmon_manage.sh.tmp.$$`
        rm ${NMON_VAR}/nmon_manage.sh.tmp.$$

        # Only manage nmon files updated within last 5 minutes (300 sec) minimum to prevent managing ended nmon files
        if [ ${nmon_age} -lt 300 ]; then
            cat $nmon_file | ${NMON_BIN}/bin/nmon2kv.sh ${NMON_BIN} ${NMON_VAR}
        fi

    done

fi

exit 0
