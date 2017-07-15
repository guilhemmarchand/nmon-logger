#####################
About the nmon-logger
#####################

* Author: Guilhem Marchand

* First release was published on starting 2014

* Purposes:

The nmon-logger for the Nmon Performance application for Splunk implements the excellent and powerful nmon binary known as Nigel's performance monitor.
Originally developed for IBM AIX performance monitoring and analysis, it is now an Open source project that made it available to many other systems.
It is fully available for any Linux flavor, and thanks to the excellent work of Guy Deffaux, it also available for Solaris 10/11 systems using the sarmon project.

The Nmon Performance monitor application for Splunk will generate performance and inventory data for your servers, and provides a rich number of monitors and tools to manage your AIX / Linux / Solaris systems.

.. image:: img/Octamis_Logo_v3_no_bg.png
   :alt: Octamis_Logo_v3_no_bg.png
   :align: right
   :target: http://www.octamis.com

**Nmon Performance is now associated with Octamis to provide professional solutions for your business, and professional support for the Nmon Performance solution.**

*For more information:*

-----------------------
What does nmon-logger ?
-----------------------

The nmon-logger package provides out of the box performance and configuration logging of your systems, and will use syslog to transport these data to your central syslog servers.

For more information about Nmon for Linux, see: http://nmon.sourceforge.net/pmwiki.php

**The nmon-logger package is provided for the 2 major syslog solutions:**

- rsyslog, starting with version 8: nmon-logger-rsyslog
- syslog-ng: nmon-logger-syslog-ng

Its main purpose it to provide an alternative and agent free way of ingesting the Nmon data into Splunk Enterprise with the Nmon Performance application.
Althought it could be used with other intelligence big data solution.

-----------------------------------------
About Nmon Performance Monitor for Splunk
-----------------------------------------

Nmon Performance Monitor for Splunk is provided in Open Source, you are totally free to use it for personal or professional use without any limitation,
and you are free to modify sources or participate in the development if you wish.

**Feedback and rating the application will be greatly appreciated.**

* Join the Google group: https://groups.google.com/d/forum/nmon-splunk-app

* App's Github page: https://github.com/guilhemmarchand/nmon-for-splunk

* Videos: https://www.youtube.com/channel/UCGWHd40x0A7wjk8qskyHQcQ

* Gallery: https://flic.kr/s/aHskFZcQBn
