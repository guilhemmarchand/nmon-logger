#!/bin/sh

# set -x

# Program name: hec_wrapper.sh
# Purpose - stream to Splunk HEC
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".
# Date - June 2014

# Version 1.0.0

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

# Which type of OS are we running
UNAME=`uname`

# file destination
userarg1=$1

# Splunk sourcetype
userarg2=$2

# Splunk source
userarg3=$3

# APP path discovery
APP="/etc/nmon-logger"

# source default nmon.conf
if [ -f $APP/default/nmon.conf ]; then
	. $APP/default/nmon.conf
fi

# source local nmon.conf, if any

# Search for a local nmon.conf
if [ -f $APP/local/nmon.conf ]; then
	. $APP/local/nmon.conf
fi

# On a per server basis, you can also set in /etc/nmon.conf
if [ -f /etc/nmon.conf ]; then
	. /etc/nmon.conf
fi

# Capture the splunk_http_url
splunk_http_url=`echo $nmon2csv_options | grep -Po "splunk_http_url\s{0,}\K[^\s]*"`

# Capture the splunk_http_token
splunk_http_token=`echo $nmon2csv_options | grep -Po "splunk_http_token\s{0,}\K[^\s]*"`

# Manage FQDN option
echo $nmon2csv_options | grep '--use_fqdn' >/dev/null
if [ $? -eq 0 ]; then
    HOST=`hostname -f`
else
    HOST=`hostname`
fi

############################################
# functions
############################################

# Store stdin
output=""
while read line ; do
	echo "$line" >> ${userarg1}
	case $output in
	"")
	    output="$line"
	    ;;
	*)
	    output="$output\n$line"
	    ;;
	esac
done

# Stream to HEC
case ${splunk_http_token} in

"insert_your_splunk_http_token")
	# Do nothing
;;

*)
	curl -s -k -H "Authorization: Splunk ${splunk_http_token}" ${splunk_http_url} -d "{\"host\": \"${HOST}\", \"sourcetype\": \"${userarg2}\", \"source\": \"${userarg3}\", \"event\": \"${output}\"}"
;;

esac

exit 0
