#!/bin/sh

# The simple script will be used for system lacking logrotate
# It should be scheduled once a day by cron

DATE=`date +%d%h-%I%p`
BASE_DIR='/var/log/nmon-logger'

cd $BASE_DIR
logfiles=`ls *.log`

for logfile in $logfiles; do
    if [ -f $BASE_DIR/$logfile ]; then
        cp $BASE_DIR/$logfile $BASE_DIR/$logfile.$DATE
        > $BASE_DIR/$logfile
        compress $BASE_DIR/$logfile.$DATE
    fi
done

find $BASE_DIR -name '*.log.*' -a -mtime +3 -exec rm {} \;

exit 0
