###############################
Introduction to Nmon processing
###############################

===============
Nmon processing
===============

The TA-nmon embeds different scripts to perform various tasks from starting nmon binaries to the creation of the final data to be indexed by Splunk.

The following items expose the main steps of the processing, the technical details of each scripts and options are globally covered by the documentation.

bin/nmon_helper.sh
^^^^^^^^^^^^^^^^^^

**The "nmon_helper.sh" script is scheduled to be run every 60 seconds by Splunk, it is responsible for various tasks such as:**

* identify the system (OS, processor architecture...)
* load default and custom configurations
* identify the best nmon binary candidate
* identify the running nmon process
* identify fifo_reader process running, and start the reader
* start the nmon binary

*Simplified representation of the processing tasks:*

.. image:: img/nmon_helper_processing.png
   :alt: nmon_helper_processing.png
   :align: center

bin/fifo_consumer.sh
^^^^^^^^^^^^^^^^^^^^

**The "fifo_consumer.sh" script is scheduled to be run every 60 seconds by Splunk, its purpose is consuming the dat files (different part of the nmon file) and stream its content to nmon2csv parsers:**

* access the fifo files, wait at least 5 seconds since its last update
* Stream the content of the files to the nmon2csv parser
* empty the nmon_data.dat files for the next cycle

bin/nmon2kv.sh|.py|.pl
^^^^^^^^^^^^^^^^^^^^^^^

**These are the nmon2kv parsers:**

* the nmon2kv.sh is a simple wrapper which will choose between the Python and Perl parser
* the content is being read in stdin, and piped to the nmon2kv Python or Perl parser
* the Python or Perf parser reads the data, does various processing tasks and generate the final files to be read
