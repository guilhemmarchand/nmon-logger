#!/bin/sh

# Program name: nmon_external_snap.sh
# Purpose - Add external command results to extend nmon data
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".  
# Date - March 2017
# Guilhem Marchand 2017/03/18, initial version

# 2017/04/29, Guilhem Marchand:         - AIX compatibility issues, detach the commands in background
# 2017/06/04, Guilhem Marchand:         - Manage nmon external data in a dedicated file

# Version 1.0.2

# For AIX / Linux / Solaris

# for more information, see:
# https://www.ibm.com/developerworks/community/blogs/aixpert/entry/nmon_and_External_Data_Collectors?lang=en

# This script will output the values for our custom external monitors
# The first field defines the name of the monitor (type field in the application)
# This monitor name must then be added to your local/nmonparser_config.json file

# 2 sections are available for nmon external monitor managements:
# - nmon_external: manage any number of fields without transposition
# - nmon_external_transposed: manage any number of fields with a notion of device / value

# note: the NMON_FIFO_PATH is a pattern that will be replaced by the nmon_helper.sh script in a copy of this script
# that lives for the time to live of the nmon process started

# CAUTION: ensure your custom command does not output any comma within the field name and value

# Number of running processes
echo "PROCCOUNT,$1,`ps -ef | wc -l`" >>NMON_FIFO_PATH/nmon_external.dat &

# Uptime information (uptime command output)
echo "UPTIME,$1,\"`uptime | sed 's/^\s//g' | sed 's/,/;/g'`\"" >>NMON_FIFO_PATH/nmon_external.dat &

# df table information
DF_TABLE=`df -k -P | sed '1d' | egrep -v '\s\/proc$|\s/dev$|\s\/run$|^tmpfs.*\/dev.*$|^tmpfs.*\/run.*$|^tmpfs.*\/sys.*$|^tmpfs.*\/var.*$' | awk '{print $6}'`
for fs in $DF_TABLE; do
    echo "DF_STORAGE,$1,`df -k -P $fs | sed '1d' | sed 's/%//g' | sed 's/,/;/g' | awk '{print $1 "," $2 "," $3 "," $4 "," $5 "," $6}'`" >>NMON_FIFO_PATH/nmon_external.dat
    echo "DF_INODES,$1,`df -i -P $fs | sed '1d' | sed 's/%//g' | sed 's/,/;/g' | awk '{print $1 "," $2 "," $3 "," $4 "," $5 "," $6}'`" >>NMON_FIFO_PATH/nmon_external.dat
done
