#!/bin/sh

# set -x

# Program name: nmon_cleaner.sh
# Compatibility: sh
# Purpose - Shell wrapper for nmon_cleaner.py / nmon_cleaner.pl
# Author - Guilhem Marchand
# Date of first publication - Jan 2016

# Releases Notes:

# - Jan 2016, V1.0.0: Guilhem Marchand, Initial version

# Version 1.0.0

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

# Python is the default choice, if it is not available launch the Perl version
PYTHON=`which python >/dev/null 2>&1`

if [ $? -eq 0 ]; then

	# Supplementary check: Ensure Python is at least 2.7 version
	python_subversion=`python --version 2>&1`

	echo $python_subversion | grep '2.7' >/dev/null

	if [ $? -eq 0 ]; then
		${NMON_BIN}/bin/nmon_cleaner.py --nmon_home ${NMON_VAR}
	else
		${NMON_BIN}/bin/nmon_cleaner.pl --nmon_home ${NMON_VAR}
	fi

else

	${NMON_BIN}/bin/nmon_cleaner.pl --nmon_home ${NMON_VAR}

fi

exit 0