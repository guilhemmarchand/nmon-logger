# Performance Monitor for Unix and Linux Systems

Copyright 2014 Guilhem Marchand

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Welcome in nmon-logger, syslog logger for Nmon

### What does nmon-logger ?

**nmon-logger** is a package that implements the excellent Nigel's Performance Monitor for AIX / Linux and sarmon for Solaris.
Using this package will provide you out of the box performance and configuration logging of your systems, and will use syslog to transport these data to your central syslog servers.

*For more information about Nmon for Linux, see*: http://nmon.sourceforge.net/pmwiki.php

The **nmon-logger** package is provided for the 2 major syslog solutions:

* rsyslog, starting with version 8
* syslog-ng

###################################
#### Notes about this package: ####
###################################

This package is expected to be used with the Nmon Performance monitor for a deployment with no Universal Forwarders for end clients.
For this to be achievied, syslog can be used as the transport layer. 

*** For rsyslog: ***

See detailed instructions in the Nmon wiki: http://nmonsplunk.wikidot.com/documentation:installation:rsyslog

*** For syslog-ng: ***

See detailed instructions in the Nmon wiki: http://nmonsplunk.wikidot.com/documentation:installation:syslog-ng

###################################
### Project:			###
###################################

Using rsyslog:

Unix / Linux --> nmon-logger --> local rsyslog --> rsyslog file monitoring --> rsyslog collector --> Splunk

Using syslog-ng:

Unix / Linux --> nmon-logger --> local syslog-ng --> syslog-ng file monitoring --> syslog-ng collector --> Splunk

###################################
### Requirements:               ###
###################################

- rsyslog v8.x minimum OR syslog-ng v3.x

- Perl (minimal)

- Python 2.7.x or Perl can be used for nmon processing steps

- Systems lacking Python 2.7.x interpreter requires Perl WITH Time::HiRes module available

###################################
### Content:                    ###
###################################

### nmon-logger-rsyslog: ###

etc/
    cron.d/nmon-logger
    logrotate.d/nmon-logger
    nmon-logger/
		bin/(various)
		default/nmon.conf
    rsyslog.d/20-nmon-logger.conf

### nmon-logger-syslog-ng: ###

etc/
    cron.d/nmon-logger
    logrotate.d/nmon-logger
    nmon-logger/
                bin/(various)
                default/nmon.conf
    syslog-ng/conf.d/nmon-logger.conf

