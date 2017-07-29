# Performance Monitor for Unix and Linux Systems

Copyright 2014-2017 Guilhem Marchand

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Welcome in nmon-logger, logger for Nmon Performance

### What does nmon-logger ?

**nmon-logger** is a package that implements the excellent Nigel's Performance Monitor for AIX / Linux and sarmon for Solaris.

Using this package provides out of the box performance and configuration logging of your systems.

Different versions of the nmon-logger are provided to transport these data using rsyslog / syslog-ng or Splunk HEC (http input)

*For more information about Nmon for Linux, see*: http://nmon.sourceforge.net/pmwiki.php

**The nmon-logger package is provided for Splunk HEC and will directly stream the data over http / https:**

* **nmon-logger-splunk-hec**

**The nmon-logger package is provided for the 2 major syslog solutions:**

* rsyslog, starting with version 8: **nmon-logger-rsyslog**
* syslog-ng: **nmon-logger-syslog-ng**

**The nmon-logger package is provided as:**

* rpm package in the "**rpm**" directory, for Linux OS based on Redhat package manager
* deb package in the "**deb**" directory, for Linux OS based on Debian package manager
* raw files, to be implemented manually on any Linux OS

**What about OS compatibility ?**

nmon-logger packages are widely tested against:

* Ubuntu (x86 and Powerpc)
* Debian (x86)
* CentOS (x86)
* RHEL (x86 and Powerpc)
* Suse (x86 and Powerpc)
* OpenSuse (x86)

**What about dependencies ?**

*Very few dependencies are required to run the nmon-logger package:*

* rsyslog (minimal version 8) for nmon-logger-rsyslog / syslog-ng for nmon-logger-syslog-ng
* the splunk-hec nmon-logger is an agent free solution and has no dependencies
* Python 2.7.x or any 2.x superior **OR** Perl with module Time:HiRes installed

**Nmon binaries ?**

The nmon-logger package has embedded binaries for most Linux OS on various processor architectures, see: http://nmon-for-splunk.readthedocs.io/en/latest/binaries.html

**What to do with nmon-logger ?**

The nmon-logger package has been designed to be used with the **Nmon Performance Monitor application for Splunk Enterprise**, see: https://github.com/guilhemmarchand/nmon-for-splunk

**Deployment scenarios:**

*Documented deployment scenarios are available here:*

* nmon-logger-splunk-hec: http://nmon-for-splunk.readthedocs.io/en/latest/splunkhec_deployment.html

* nmon-logger-rsyslog: http://nmon-for-splunk.readthedocs.io/en/latest/rsyslog_deployment.html

* nmon-logger-syslog-ng: http://nmon-for-splunk.readthedocs.io/en/latest/syslogng_deployment.html

**What about Vagrant and Ansible directories ?**

*To easily test the nmon-logger / Nmon Performance Monitor for Splunk Enterprise solution, the following packages are provided (implementing Vagrant, VirtualBox and Ansible automation):*

* vagrant-ansible-demo-splunk-hec

* vagrant-ansible-demo-rsyslog

* vagrant-ansible-demo-syslog-ng

*Requirements*:

* vagrant, see: https://www.vagrantup.com/downloads.html

* Oracle VirtualBox: https://www.virtualbox.org/wiki/Downloads

**Using these package will create a fully operational installation of Splunk, Nmon Performance monitor application, splunk-hec / rsyslog / syslog-ng and nmon-logger in a totally automated process, up in less than 10 minutes !**

### Quick description of packages content

#### nmon-logger-splunk-hec:

    etc/
        cron.d/nmon-logger
        logrotate.d/nmon-logger
        nmon-logger/
            bin/(various)
            default/nmon.conf
            default/app.conf

#### nmon-logger-rsyslog:

    etc/
        cron.d/nmon-logger
        logrotate.d/nmon-logger
        nmon-logger/
            bin/(various)
            default/nmon.conf
            default/app.conf
        rsyslog.d/20-nmon-logger.conf

#### nmon-logger-syslog-ng:

    etc/
        cron.d/nmon-logger
        logrotate.d/nmon-logger
        nmon-logger/
            bin/(various)
            default/nmon.conf
            default/app.conf
        syslog-ng/conf.d/nmon-logger.conf

### How it works and what to expect with the nmon-logger

#### nmon data generation, parsing and logging

*1 minute after you installed the nmon-logger package, the data collection will automatically start on the host, which can be observed by nmon user processes:*

    ps -fu nmon
    UID        PID  PPID  C STIME TTY          TIME CMD
    nmon      5454     1  0 21:27 ?        00:00:00 /etc/nmon-logger/bin/linux/ubuntu/nmon_x86_64_ubuntu14 -f -T -d 1500 -s 60 -c 120 -p

*nmon processes management is achieved by the nmon_helper.sh script, scheduled by cron in the nmon-logger cron.d file:*
 
    /etc/cron.d/nmon-logger 
    # The nmon_helper.sh is responsible for nmon binary launch and requires arguments: <arg1: binaries path> <arg2: log path>
    */1 * * * * nmon /etc/nmon-logger/bin/nmon_helper.sh /etc/nmon-logger /var/log/nmon-logger >> /var/log/nmon-logger/nmon_collect.log 2>&1

*nmon files are stored in "/var/log/nmon-logger/var/nmon_repository/":*
 
    ls -ltr /var/log/nmon-logger/var/nmon_repository/
    total 36
    -rw-rw-r-- 1 nmon nmon 33639 Sep  2 21:34 rsyslog-client1_160902_2127.nmon

*The activity (formerly "nmon_collect") of nmon_helper.sh is logged in:*

    /var/log/nmon-logger/nmon_collect.log
 
*Every minute, the nmon_manage.sh will read and send the nmon file to parsers if required, scheduled by cron.d:*

    # The nmon_manage.sh is responsible for launching nmon kv converter and requires arguments: <arg1: binaries path> <arg2: log path>
    */1 * * * * nmon /etc/nmon-logger/bin/nmon_manage.sh /etc/nmon-logger /var/log/nmon-logger >> /var/log/nmon-logger/nmon_processing.log 2>&1

*The parsing activity (formerly "nmon_processing") is logged in:*
 
    /var/log/nmon-logger/nmon_processing.log
 
*Parsers will generate configuration data (formerly "nmon_config") and performance data (formerly "nmon_performance") in a key=value format in:*

    /var/log/nmon-logger/nmon_configdata.log

    /var/log/nmon-logger/nmon_perfdata.log

*Every 4 hours the nmon_cleaner.sh script will run various maintenance tasks, it is scheduled by cron.d:*

    # The nmon_cleaner.sh is responsible for nmon files cleaning and requires arguments: <arg1: binaries path> <arg2: log path>
    0 */4 * * * nmon sleep 30; /etc/nmon-logger/bin/nmon_cleaner.sh /etc/nmon-logger /var/log/nmon-logger >> /var/log/nmon-logger/nmon_clean.log 2>&1

*Its activity is logged in:*

    /var/log/nmon-logger/nmon_clean.log

#### Splunk HEC forwarding

When deploying the nmon-logger-splunk-hec, you must configure the target URL (the Splunk HEC endpoint URL) and the HEC token.

**Create a "local" directory:**

    mkdir /etc/nmon-logger/local

**Create a "local/nmon.conf", copy the "nmon2csv_options" configuration (from the default/nmon.conf) and insert your URL and token:**

    # HEC server configuration    
    nmon2csv_options="--mode fifo --silent --splunk_http_url https://192.168.33.100:8088/services/collector/event --splunk_http_token CEE56643-BA2D-48EE-94EF-AD0909718B2A"

#### syslog forwarding

*Using rsyslog or syslog-ng file monitoring facilities, the content of these log files is permanently monitored and forwarded to your remote syslog servers*

#### log files rotation (logrotate)

*Finally, the logrotate daemon will take care of achieving log files rotation. (automatically reloading rsyslog/syslog-ng at the end of the file rotation process)*
