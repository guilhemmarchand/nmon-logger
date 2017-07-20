###############################
Operating Systems compatibility
###############################

================
OS compatibility
================

**The nmon-logger package is provided as:**

- rpm package in the "rpm" directory, for Linux OS based on Redhat package manager
- deb package in the "deb" directory, for Linux OS based on Debian package manager
- raw files, to be implemented manually on any Linux OS

**nmon-logger packages are widely tested against:**

- CentOS
- Debian
- Ubuntu

**Very few dependencies are required to run the nmon-logger package:**

- rsyslog (minimal version 8) for nmon-logger-rsyslog / syslog-ng for nmon-logger-syslog-ng
- Python 2.7.x or any 2.x superior OR Perl with module Time:HiRes installed

**Nmon binaries ?**

The nmon-logger package has embedded binaries for most Linux OS on various processor architectures, see: http://nmon-for-splunk.readthedocs.io/en/latest/binaries.html
