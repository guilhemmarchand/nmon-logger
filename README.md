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

**The nmon-logger package is provided for the 2 major syslog solutions:**

* rsyslog, starting with version 8: **nmon-logger-rsyslog**
* syslog-ng: **nmon-logger-syslog-ng**

**The nmon-logger package is provided as:**

* rpm package in the "**rpm**" directory, for Linux OS based on Redhat package manager
* deb package in the "**deb**" directory, for Linux OS based on Debian package manager
* raw files, to be implemented manually on any Linux OS

**What about OS compatibility ?**

nmon-logger packages are widely tested against:

* CentOS
* Debian
* Ubuntu

**What about dependencies ?**

*Very few dependencies are required to run the nmon-logger package:*

* rsyslog (minimal version 8) for nmon-logger-rsyslog / syslog-ng for nmon-logger-syslog-ng
* Python 2.7.x or any 2.x superior **OR** Perl with module Time:HiRes installed

**Nmon binaries ?**

The nmon-logger package has embedded binaries for most Linux OS on various processor architectures, see: http://nmon-for-splunk.readthedocs.io/en/latest/binaries.html

**What to do with nmon-logger ?**

The nmon-logger package has been technically designed to be use with the **Nmon Performance Monitor application for Splunk Enterprise**, see: https://github.com/guilhemmarchand/nmon-for-splunk
Therefore, the nmon-logger package uses rsyslog / syslog-ng to transfer data which is application independent, so it is technically possible to analyse these data with any other modern data analytic solution.

**Deployment scenarios:**

*Documented deployment scenarios are available here:*

* nmon-logger-rsyslog: http://nmon-for-splunk.readthedocs.io/en/latest/rsyslog_deployment.html

* nmon-logger-syslog-ng: http://nmon-for-splunk.readthedocs.io/en/latest/syslogng_deployment.html

**What about Vagrant and Ansible directories ?**

*To easily the nmon-logger / Nmon Performance Monitor for Splunk Enterprise solution, you will find 2 packages implementing Vagrant, VirtualBox and Ansible automation:*

* vagrant-ansible-demo-rsyslog

* vagrant-ansible-demo-syslog-ng

*Requirements*:

* vagrant, see: https://www.vagrantup.com/downloads.html

* Oracle VirtualBox: https://www.virtualbox.org/wiki/Downloads

**Using these package will create a fully operational installation of Splunk, Nmon Performance monitor application, rsyslog/syslog-ng and nmon-logger in a totally automated process, up in less than 10 minutes !**

### Packages content

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

