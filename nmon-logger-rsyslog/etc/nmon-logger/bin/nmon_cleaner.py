#!/usr/bin/env python

# Program name: nmon_cleaner.py
# Compatibility: Python 2.7
# Purpose - Clean nmon data upon retention expiration
# Author - Guilhem Marchand
# Date of first publication - Jan 2016

# Releases Notes:

# - Jan 2016, V1.0.0: Guilhem Marchand, Initial version

# Load libs

from __future__ import print_function

import sys
import os
import glob
import time
import logging
import platform
import re
import argparse

# Cleaner version
version = '1.0.0'

# LOGGING INFORMATION:
# - The program uses the standard logging Python module to display important messages in Splunk logs
# - Every message of the script will be indexed and accessible within Splunk splunkd logs

#################################################
#      Functions
#################################################

# Disallow negative value in parser

def check_negative(value):

    ivalue = int(value)
    if ivalue < 0:
        raise argparse.ArgumentTypeError("%s is an invalid positive int value" % value)
    return ivalue

#################################################
#      Arguments Parser
#################################################

# Define Arguments
parser = argparse.ArgumentParser()

parser.add_argument('--maxseconds_nmon', action='store', dest='maxseconds_nmon', type=check_negative,
                    help='Set the maximum file retention in seconds for nmon files, every files older'
                         ' than this value will be permanently removed')

parser.add_argument('--nmon_home', action='store', dest='nmon_home',
                    help='Set the Nmon Home directory (mandatory)')

parser.add_argument('--version', action='version', version='%(prog)s ' + version)

args = parser.parse_args()

#################################################
#      Variables
#################################################

# Set logging format
logging.root
logging.root.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(levelname)s %(message)s')
handler = logging.StreamHandler()
handler.setFormatter(formatter)
logging.root.addHandler(handler)

# Current date
now = time.strftime("%c")

# Set maxseconds
maxseconds_nmon = args.maxseconds_nmon

# Check Arguments
if len(sys.argv) < 2:
    print ("\n%s" % os.path.basename(sys.argv[0]))
    print ("\nUtilization:\n")
    print ("- mandatory: Provide the -o or --nmon_home <full path> the Nmon home directory that contains directories "
           "to maintain")
    print ("- Optional: Use the --maxseconds_nmon <time limit in sec> to set the maximum file age retention allowed"
           " for nmon files \n")
    sys.exit(0)

# Definition of Nmon Home directory is mandatory
if not (args.nmon_home):
    logging.error('Nmon Home directory were not provided, this is mandatory.')
    sys.exit(1)
else:
    nmon_home = args.nmon_home

# Guest Operation System type
ostype = platform.system().lower()

# If running Windows OS (used for directory identification)
is_windows = re.match(r'^win\w+', (platform.system().lower()))

# Python version
python_version = platform.python_version()

# Config data repository
if is_windows:
    NMON_DIR = nmon_home + '\\var\\nmon_repository\\'
else:
    NMON_DIR = nmon_home + '/var//nmon_repository/'

# Check Nmon Home
if not os.path.isdir(nmon_home):
    msg = 'The main var directory ' + nmon_home + ' has not been found, there is no need to run now.'
    logging.info(msg)
    sys.exit(0)

# Starting time of process
start_time = time.time()

####################################################################
#           Main Program
####################################################################

# Default value for NMON retention is 600 seconds (10 min) since the last last modification
if maxseconds_nmon is None:
    maxseconds_nmon = 600

# Show current time
msg = now + " Starting nmon cleaning"
logging.info(msg)

# Display some basic information about us
msg = "Nmon Root Directory: " + str(nmon_home) + " nmon_cleaner version: " + str(version) \
      + " Python version: " + str(python_version)
logging.info(msg)

# Proceed to NMON cleaning

# cd to directory
DIR = NMON_DIR

os.chdir(DIR)

# Verify we have data to manage
counter = len(glob.glob1(DIR, "*.nmon"))

# print (counter)

if counter == 0:
    msg = 'No files found in directory: ' + str(DIR) + ', no action required.'
    logging.info(msg)

else:

    # cd to directory
    os.chdir(DIR)

    # counter of files with retention expired
    counter_expired = 0

    curtime = time.time()
    limit = maxseconds_nmon

    for xfile in glob.glob('*.nmon'):

        filemtime = os.path.getmtime(xfile)

        if curtime - filemtime > limit:

            counter_expired += 1

            size_mb = os.path.getsize(xfile)/1000.0/1000.0
            size_mb = format(size_mb, '.2f')

            mtime = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(filemtime))  # Human readable datetime

            msg = 'Max set retention of ' + str(maxseconds_nmon) + ' seconds expired for file: ' + xfile +\
                  ' size(MB): ' + str(size_mb) + ' mtime: ' + str(mtime)
            logging.info(msg)

            os.remove(xfile)  # Permanently remove the file!

    msg = str(counter_expired) + ' files were permanently removed due to retention expired for directory ' + DIR
    logging.info(msg)

###################
# End
###################

# Time required to process
end_time = time.time()
result = "Elapsed time was: %g seconds" % (end_time - start_time)
logging.info(result)

# exit
sys.exit(0)
