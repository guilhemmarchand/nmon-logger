#!/bin/sh

# set -x

# Program name: nmon2kv.sh
# Compatibility: sh
# Purpose - Shell wrapper for nmon2kv.py / nmon2kv.pl
# Author - Guilhem Marchand
# Disclaimer: This script is provided as it is, with absolutely no warranty
# Date of first publication - Jan 2016

# Licence:

# Copyright 2016 Guilhem Marchand

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Releases Notes:

# - Jan 2014, V1.0.0: Guilhem Marchand, Initial version


# Version 1.0.0

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

# Set tmp directory
TMP_DIR="/tmp"

# Verify TMP_DIR is writable
if [ ! -w ${TMP_DIR} ]; then
    echo "`date`, ${HOST} ERROR, temp directory ${TMP_DIR} is not writable."
	exit 1
fi

# silently remove tmp file (testing exists before rm seems to cause trouble on some old OS)
rm -f ${TMP_DIR}/nmon2kv.temp.*

# Set nmon_temp
nmon_temp=${TMP_DIR}/nmon2kv.temp.$$

####################################################################
#############		Main Program 			############
####################################################################

# Store arguments sent to script
userarg1=$1
userarg2=$2

NMON_BIN=${userarg1}
NMON_VAR=${userarg2}

# Store stdin
while read line ; do
	echo "$line" >> ${nmon_temp}
done

# Python is the default choice, if it is not available launch the Perl version
PYTHON=`which python >/dev/null 2>&1`

if [ $? -eq 0 ]; then

	# Check Python version, nmon2kv.py compatibility starts with Python version 2.6.6
	python_subversion=`python --version 2>&1`

	case $python_subversion in
	
	*" 2.7"*)
		cat ${nmon_temp} | ${NMON_BIN}/bin/nmon2kv.py --nmon_var ${NMON_VAR} ;;
		
	*)
		cat ${nmon_temp} | ${NMON_BIN}/bin/nmon2kv.pl --nmon_var ${NMON_VAR} ;;
	
	esac

else

	cat ${nmon_temp} | ${NMON_BIN}/bin/nmon2kv.pl --nmon_var ${NMON_VAR}

fi

# Remove temp
rm -f ${nmon_temp}

exit 0