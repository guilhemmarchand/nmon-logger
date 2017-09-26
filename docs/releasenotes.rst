#########################################
Release notes
#########################################

^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
What has been fixed by release
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

========
V2.0.10:
========

- fix: reactivating the JFSFILE / JFSINODE collections until new core release is available to prevent missing features

=======
V2.0.9:
=======

- fix: Python parser - header detection correction for nmon external monitoring
- feature: Add df information for improved file system monitoring and storage capacity planning
- fix: Perl parser issue - UARG parsing issue for AIX #5

=======
V2.0.8:
=======

- fix: Python parser - preserve data ordering when possible during key value transformation

=======
V2.0.7:
=======

- fix: Python parser issue - epoch time stamp incorrectly parsed for dynamic data #4

=======
V2.0.6:
=======

- fix: corrections in hec_wrapper.sh (missing log_date function, check curl availability)

=======
V2.0.5:
=======

- fix: from TA-nmon - AIX - Better management of compatibility issue with topas-nmon not supporting the -y option #43
- fix: from TA-nmon - AIX - fix repeated and not justified pid file removal message #44
- fix: from TA-nmon - ALL OS - nmon_helper.sh code improvements #45
- feature: from TA-nmon - Optimize nmon_processing output and reduce volume of data to be generated #37
- fix: from TA-nmon - Linux issue: detection of default/nmon.conf rewrite required is incorrect #41
- fix: from TA-nmon - Error in nmon_helper.sh - bad analysis of external snap processes #42

=======
V2.0.4:
=======

- fix: nmon2kv.py issue when using the --use_fqdn option (useless call to get_fqdn function, undesired output)
