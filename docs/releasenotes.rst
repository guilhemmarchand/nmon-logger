#########################################
Release notes
#########################################

^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
What has been fixed by release
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

========
V2.0.5:
========

- fix: from TA-nmon - AIX - Better management of compatibility issue with topas-nmon not supporting the -y option #43
- fix: from TA-nmon - AIX - fix repeated and not justified pid file removal message #44
- fix: from TA-nmon - ALL OS - nmon_helper.sh code improvements #45
- feature: from TA-nmon - Optimize nmon_processing output and reduce volume of data to be generated #37
- fix: from TA-nmon - Linux issue: detection of default/nmon.conf rewrite required is incorrect #41
- fix: from TA-nmon - Error in nmon_helper.sh - bad analysis of external snap processes #42

========
V2.0.4:
========

- fix: nmon2kv.py issue when using the --use_fqdn option (useless call to get_fqdn function, undesired output)
