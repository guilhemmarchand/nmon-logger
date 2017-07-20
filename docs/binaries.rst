====================
Scripts and Binaries
====================

***********************************
Embedded Scripts in the nmon-logger
***********************************

**nmon_helper:**

 * bin/nmon_helper.sh:

This shell script is being used by the application to launch Nmon binaries whenever it is detected as required.

It is as well responsible in launching the fifo_reader scripts. (introduced in version 1.3.x)

**fifo_reader:**

* bin/fifo_reader.pl
* bin/fifo_reader.py
* bin/fifo_reader.sh

These scripts are continuously running as back ground processes on server running the technical addons.
Their purpose is to read the fifo files (named pipe) nmon processes are writing to, and extract the different typologies of data from them nmon data

**fifo_consumer:**

* bin/fifo_consumer.sh

This script is scheduled by default to run every 60 seconds.
Its purpose to recompose the nmon flaw of data to be parsed by the nmon parser scripts. (see bellow)

**nmon_parser:**

 * bin/nmon2kv.sh | bin/nmon2kv.py | bin/nmon2kv.pl:

Shell / Python / Perl scripts used to manage and process Nmon raw data into multiple csv files being indexed by Splunk

The Shell script is a wrapper script to Python / Perl scripts. (decision is made on local interpreter avaibility with Python as the default choice)

**nmon_cleaner:**

 * bin/nmon_cleaner.sh / bin/nmon_cleaner.py / nmon_cleaner.pl

Shell / Python / Perl scripts used to manage retention and purge of old nmon data.

Alternatively, it will also ensure that no outdated csv data is being left by Splunk in Performance and Configuration repositories

The Shell script is a wrapper script to Python / Perl scripts. (decision is made on local interpreter avaibility with Python as the default choice)

********************************
Embedded Binaries in the TA-nmon
********************************

The TA-nmon embeds Nmon binaries for Linux vendors and Solaris OS.
AIX embeds by default its own version of Nmon, known as "topas-nmon".

**For Linux OS:**

 * bin/linux: Main directory for Linux specific Nmon binaries
 * bin/linux/amzn: 64 bits binaries for Amazon Linux (AMI)
 * bin/linux/centos: 32/64 bits binaries for Centos
 * bin/linux/debian: 32/64 bits binaries for Debian GNU/Linux
 * bin/linux/fedora: 32/64 bits binaries for Fedora project
 * bin/linux/generic: 32/64/ia64/power/mainframe binaries compiled for generic Linux
 * bin/linux/mint: 32/64 bits binaries for Linux Mint
 * bin/linux/opensuse: 32/64 bits binaries for Linux Opensuse
 * bin/linux/ol: 32/64 bits binaries for Oracle Linux
 * bin/linux/rhel: 32/64/ia64/mainframe/power binaries for Redhat Entreprise Server
 * bin/linux/sles: 32/64/ia64/mainframe/power binaries for Suse Linux Entreprise Server
 * bin/linux/ubuntu: 32/64/power/arm binaries for Ubuntu Linux
 * bin/linux/arch: 32/64 bits binaries for Archlinux
 * bin/raspbian: arms binaries for Raspbian Linux

Most of these binaries comes from the official Nmon Linux project site.
On x86 processor and for Centos / Debian / Ubuntu / Oracle Linux these binaries are being compiled by myself using Vagrant and Ansible automation. (See https://github.com/guilhemmarchand/nmon-binaries)

Associated scripts resource (nmon_helper.sh) will try to use the better version of Nmon available, it will fall back to generic or system embedded if none of specially compiled versions can fit the system.

**For Solaris OS:**

*sarmon binaries for Oracle Solaris x86 and Sparc:*

 * bin/sarmon_bin_i386: sarmon binaries for Solaris running on x86 arch
 * bin/sarmon_bin_sparc: sarmon binaris for Solaris running on sparc arch

sarmon binaries comes from the official sarmon site project.

**For AIX**:

Nmon is shipped within AIX by default with topas-nmon binary.
