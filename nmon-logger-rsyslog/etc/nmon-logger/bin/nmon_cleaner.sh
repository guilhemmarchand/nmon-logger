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

# Set host
HOST=`hostname`

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

###### Start cleaner ######

case ${INTERPRETER} in

"python")
		${NMON_BIN}/bin/nmon_cleaner.py --nmon_home ${NMON_VAR} ;;

"perl")
		${NMON_BIN}/bin/nmon_cleaner.pl --nmon_home ${NMON_VAR} ;;

esac

exit 0
