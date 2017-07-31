#!/usr/bin/env bash
# set -x

PWD=`pwd`
DST=${PWD}

for app in nmon-logger-rsyslog nmon-logger-syslog-ng nmon-logger-splunk-hec; do

	version=`grep 'version =' ../${app}/etc/nmon-logger/default/app.conf | awk '{print $3}' | sed 's/\.//g'`
	cd ../${app}/	
	tar -czf ${DST}/${app}_${version}.tgz etc
	echo "Wrote: ${app}_${version}.tgz"

	cd $PWD

done

exit 0

