#!/usr/bin/env python

# Program name: nmon2kv.py
# Compatibility: Python 2x
# Purpose - convert nmon files into kv flow, this script is a back ported version of the origin csv2mon.py
# developped for the Nmon Performance Monitor application for Splunk, see https://apps.splunk.com/app/1753
# Author - Guilhem Marchand
# Disclaimer: This script is provided as it is, with absolutely no warranty
# Date of first publication - Jan 2016

# Licence:

# Copyright 2016 Guilhem Marchand

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Releases Notes:

# - Jan 2014, V1.0.0: Guilhem Marchand, Initial version

# Load libs

from __future__ import print_function

import sys
import re
import os
import time
import datetime
import csv
import logging
import cStringIO
import platform
import optparse

# Converter version
nmon2csv_version = '1.0.0'

# LOGGING INFORMATION:
# - The program uses the standard logging Python module to display important messages in Splunk logs
# - When we want messages to be indexed within Splunk nmon_processing sourcetype, display the message
# in stdout. (splunk won't index logging messages)
# Typically, functional errors will be displayed in stdout while technical failure will be logged

#################################################
#      Parameters
#################################################

# Customizations goes here:

# Sections of Performance Monitors with standard dynamic header but no "device" notion that would require the data
# to be transposed.
# You can add or remove any section depending on your needs
static_section = ["CPUnn", "CPU_ALL", "FILE", "MEM", "PAGE", "MEMNEW", "MEMUSE", "PROC", "VM", "NFSSVRV2",
                  "NFSSVRV3", "NFSSVRV4", "NFSCLIV2", "NFSCLIV3", "NFSCLIV4"]

# Some specific sections per OS
Solaris_static_section = ["PROCSOL"]

# Some specific sections per OS
AIX_static_section = ["LPAR", "POOLS"]

# This is the TOP section which contains Performance data of top processes
# It has a specific structure and requires specific treatment
top_section = ["TOP"]

# This is the UARG section which contains full command line arguments with some other information such as PID, user,
# group and so on.
# It has a specific structure and requires specific treatment
uarg_section = ["UARG"]

# Sections of Performance Monitors with "device" notion, data needs to be transposed by time to be fully exploitable
# This particular section will check for up to 10 subsection per Performance Monitor
# By default, Nmon create a new subsection (add an increment from 1 to x) per step of 150 devices
# 1500 devices (disks) will be taken in charge in default configuration
dynamic_section1 = ["DISKBUSY", "DISKBSIZE", "DISKREAD", "DISKWRITE", "DISKXFER", "DISKRIO", "DISKWIO", "DISKREADSERV",
                    "DISKWRITESERV"]

# Sections of Performance Monitors with "device" notion, data needs to be transposed by time to be fully exploitable
dynamic_section2 = ["IOADAPT", "NETERROR", "NET", "NETPACKET", "JFSFILE", "JFSINODE", "FCREAD", "FCWRITE", "FCXFERIN",
                    "FCXFEROUT"]

# Sections of Performance Monitors for Solaris

# Zone, Project, Task... performance
solaris_WLM = ["WLMPROJECTCPU", "WLMZONECPU", "WLMTASKCPU", "WLMUSERCPU", "WLMPROJECTMEM", "WLMZONEMEM", "WLMTASKMEM",
               "WLMUSERMEM"]

# Veritas Storage Manager
solaris_VxVM = ["VxVMREAD", "VxVMWRITE", "VxVMXFER", "VxVMBSIZE", "VxVMBUSY", "VxVMSVCTM", "VxVMWAITTM"]

solaris_dynamic_various = ["DISKSVCTM", "DISKWAITTM"]

# AIX only dynamic sections
AIX_dynamic_various = ["SEA", "SEAPACKET", "SEACHPHY"]

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

# Initial states for Analysis
realtime = False
colddata = False

# Starting time of process
start_time = time.time()

# Initialize some default values
day = "-1"
month = "-1"
year = "-1"
hour = "-1"
minute = "-1"
second = "-1"
ZZZZ_timestamp = "-1"
INTERVAL = "-1"
SNAPSHOTS = "-1"
sanity_check = "-1"

#################################################
#      Arguments
#################################################

parser = optparse.OptionParser(usage='usage: %prog [options]', version='%prog '+nmon2csv_version)

parser.set_defaults(nmon_var='/var/log/nmon', mode='auto', json_mode='pretty', dumpargs=False)

parser.add_option('-o', '--nmon_var', action='store', type='string', dest='nmon_var',
                  help='sets the output Home directory for Nmon (Default: %default)')
opmodes = ['auto', 'realtime', 'colddata']
parser.add_option('-m', '--mode', action='store', type='choice', dest='mode', choices=opmodes,
                  help='sets the operation mode (Default: %default); supported modes: ' + ', '.join(opmodes))
jsonmodes = ['pretty', 'dump']
parser.add_option('-j', '--json_mode', action='store', type='string', dest='json_mode',
                  help='sets the output mode for json data (Default: %default, options: dump / pretty)')
parser.add_option('--nokvdelim', action='store_true', dest='nokvdelim', default=False, help='Deactivate delimitor for '
                                                                                       'kv value (activated '
                                                                                       'by default)')
parser.add_option('--dumpargs', action='store_true', dest='dumpargs',
                  help='only dump the passed arguments and exit (for debugging purposes only)')
parser.add_option('--debug', action='store_true', dest='debug', help='Activate debug for testing purposes')

(options, args) = parser.parse_args()

if options.dumpargs:
    print("options: ", options)
    print("args: ", args)
    sys.exit(0)

# Set debug mode
if options.debug:
    debug = True
else:
    debug = False

# Set kv delimitor
if options.nokvdelim:
    kvdelim = False
else:
    kvdelim = True

# Guest Operation System type
ostype = platform.system().lower()

# If running Windows OS (used for directory identification)
is_windows = re.match(r'^win\w+', (platform.system().lower()))

# Current date
now = time.strftime("%d-%m-%Y %H:%M:%S")

# Current date in epoch time
if is_windows:
    now_epoch = time.time()
else:
    now_epoch = time.strftime("%s")

# timestamp used to name csv files
csv_timestamp = time.strftime("%Y%m%d%H%M%S")

# Python version
python_version = platform.python_version()

# NMON_VAR variable
if options.nmon_var:
    NMON_VAR = options.nmon_var
else:
    NMON_VAR = '/var/log/nmon'

# Verify nmon_var
if not os.path.exists(NMON_VAR):
    try:
        os.makedirs(NMON_VAR)
    except Exception as ex:
        logging.error("Unable to create data output directory '%s': %s" % (NMON_VAR, ex))
        sys.exit(1)

# APP_VAR directory
if is_windows:
    APP_VAR = NMON_VAR + '\\var'
else:
    APP_VAR = NMON_VAR + '/var'
if not os.path.exists(APP_VAR):
    os.mkdir(APP_VAR)

# ID reference file, will be used to temporarily store the last execution result for a given nmon file,
# and prevent Splunk from generating duplicates by relaunching the conversion process
# Splunk when using a custom archive mode, launches twice the custom script

# Supplementary note: Since V1.1.0, the ID_REF is overwritten if running real time mode
if is_windows:
    ID_REF = APP_VAR + '\\id_reference.txt'
else:
    ID_REF = APP_VAR + '/id_reference.txt'

# Config Reference file
if is_windows:
    CONFIG_REF = APP_VAR + '\\config_reference.txt'
else:
    CONFIG_REF = APP_VAR + '/config_reference.txt'

# BBB extraction flag
if is_windows:
    BBB_FLAG = APP_VAR + '\\BBB_status.flag'
else:
    BBB_FLAG = APP_VAR + '/BBB_status.flag'

# CSV Perf data repository
if is_windows:
    DATA_DIR = APP_VAR
else:
    DATA_DIR = APP_VAR

# CSV output repository
if is_windows:
    CONFIG_DIR = APP_VAR
else:
    CONFIG_DIR = APP_VAR

#################################################
#      Functions
#################################################

# Return current time stamp in Nmon fashion
def currenttime():
    now = time.strftime("%d-%m-%Y %H:%M:%S")

    return now


# Replace % for common sections
def subpctreplace(line):
    # Replace bank char followed by %
    line = re.sub(r'\s%', '_PCT', line)

    # Replace % if part of a word
    line = re.sub(r'(?<=[a-zA-Z0-9])%', '_PCT', line)

    # Replace % at beginning of a word
    line = re.sub(r'(?<=[a-zA-Z0-9,])%(?=[a-zA-Z0-9]+|$)', 'PCT', line)

    # Replace any other %
    line = re.sub(r'%', '_PCT', line)

    return line


# Replace % for TOP section only
def subpcttopreplace(line):
    # Replace % (specific for TOP)
    line = re.sub(r'%', 'pct_', line)

    return line


# Replace others for all sections
def subreplace(line):
    # Replace blank space between 2 groups of chars
    line = re.sub(r'(?<=[a-zA-Z0-9]) (?=[a-zA-Z0-9]+|$)', '_', line)

    # Replace +
    line = re.sub(r'\+', '', line)

    # Replace "(" by "_"
    line = re.sub(r'\(', '_', line)

    # Replace ")" by nothing
    line = re.sub(r'\)', '', line)

    # Replace =0 by nothing
    line = re.sub(r'=0', '', line)

    return line


# Convert month names (eg. JANV) to month numbers (eg. 01)
def monthtonumber(mydate):
    month_to_numbers = {'JAN': '01', 'FEB': '02', 'MAR': '03', 'APR': '04', 'MAY': '05', 'JUN': '06', 'JUL': '07',
                        'AUG': '08', 'SEP': '09', 'OCT': '10', 'NOV': '11', 'DEC': '12'}

    for k, v in month_to_numbers.items():
        mydate = mydate.replace(k, v)

    return mydate


# Convert month numbers (eg. 01) to month names (eg. JANV)
def numbertomonth(month):
    numbers_to_month = {'01': 'JAN', '02': 'FEB', '03': 'MAR', '04': 'APR', '05': 'MAY', '06': 'JUN', '07': 'JUL',
                        '08': 'AUG', '09': 'SEP', '10': 'OCT', '11': 'NOV', '12': 'DEC'}

    for k, v in numbers_to_month.items():
        month = month.replace(k, v)

    return month


# Open ID_REF, global to be used in function or current scope
def openRef():
    global ref
    ref = open(ID_REF, "w")


#Convert csv data into key=value format
def write_kv(input, kv_file):
    with open(kv_file, 'ab') as f:
        reader = csv.DictReader(input)

        if kvdelim:
            for row in reader:
                for k, v in row.items():
                    f.write("%s=\"%s\" " % (k,v))
                f.write('\n')
        else:
            for row in reader:
                for k, v in row.items():
                    f.write("%s=%s " % (k,v))
                f.write('\n')


####################################################################
#           Main Program
####################################################################

#################################
# Retrieve NMON data from stdin #
#################################

# Read nmon data from stdin
data = sys.stdin.readlines()

# Number of lines read
nbr_lines = len(data)

# Size of data read
bytes_total = len(''.join(data))

# Show current time and number of lines
msg = "nmon2csv:" + currenttime() + " Reading NMON data: " + str(nbr_lines) + " lines" + " " +\
      str(bytes_total) + " bytes"
logging.info(msg)

# Show Splunk Root Directory
msg = 'Splunk Root Directory ($NMON_VAR): ' + str(NMON_VAR)
logging.info(msg)

# Show program version
msg = "nmon2csv version: " + str(nmon2csv_version)
logging.info(msg)

# Show type of OS we are running
logging.info('Guest Operating System:' + str(ostype))

# Show Python Version
logging.info('Python version:' + python_version)

# Prevent managing empty file
count = 0

# Exit if empty with error message
for line in data:
    count += 1

if count < 1:
    logging.error('Empty Nmon file!')
    sys.exit(1)

##################################################
# Extract Various data from AAA and BBB sections #
##################################################

# Set some default values
SN = "-1"
HOSTNAME = "-1"
DATE = "-1"
TIME = "-1"
logical_cpus = "-1"
virtual_cpus = "-1"
OStype = "Unknown"

for line in data:

    # Set HOSTNAME
    host = re.match(r'^(AAA),(host),(.+)\n', line)
    if host:
        HOSTNAME = host.group(3)
        logging.info("HOSTNAME:" + str(HOSTNAME))

    # Set VERSION
    version = re.match(r'^(AAA),(version),(.+)\n', line)
    if version:
        VERSION = version.group(3)
        logging.info("NMON VERSION:" + str(VERSION))

    # Set SN
    sn = re.match(r'^(BBB.+)(systemid.+)(IBM,)(\w+)(.+)\n', line)
    if sn:
        SN = sn.group(4)
        logging.info("SerialNumber:" + str(SN))

    # Set DATE
    date = re.match(r'^(AAA),(date),(.+)\n', line)
    if date:
        DATE = date.group(3)
        logging.info("DATE of Nmon data:" + str(DATE))

    # Set date details
    date_details = re.match(r'(AAA,date,)([0-9]+)[/|\-]([a-zA-Z-0-9]+)[/|\-]([0-9]+)', line)
    if date_details:
        day = date_details.group(2)
        month = date_details.group(3)
        year = date_details.group(4)

    # Set TIME
    time_match = re.match(r'^(AAA),(time),(.+)\n', line)
    if time_match:
        TIME = time_match.group(3)
        logging.info("TIME of Nmon Data:" + str(TIME))

    # Set TIME DETAILS
    time_details = re.match(r'(AAA,time,)([0-9]+).([0-9]+).([0-9]+)', line)
    if time_details:
        hour = time_details.group(2)
        minute = time_details.group(3)
        second = time_details.group(4)

    # Set INTERVAL
    interval = re.match(r'^(AAA),(interval),(.+)\n', line)
    if interval:
        INTERVAL = interval.group(3)
        logging.info("INTERVAL:" + str(INTERVAL))

    # Set SNAPSHOTS
    snapshots = re.match(r'^(AAA),(snapshots),(.+)\n', line)
    if snapshots:
        SNAPSHOTS = snapshots.group(3)
        logging.info("SNAPSHOTS:" + str(SNAPSHOTS))

    # Set logical_cpus (Note: AIX systems for example will have values behind AAA,cpus - should use the second
    # by default if it exists)
    LOGICAL_CPUS = re.match(r'^(AAA),(cpus),(.+),(.+)\n', line)
    if LOGICAL_CPUS:
        logical_cpus = LOGICAL_CPUS.group(4)
        logging.info("logical_cpus:" + str(logical_cpus))
    else:
        # If not defined in second position, set it from first
        LOGICAL_CPUS = re.match(r'^(AAA),(cpus),(.+)\n', line)
        if LOGICAL_CPUS:
            logical_cpus = LOGICAL_CPUS.group(3)
            logging.info("logical_cpus:" + str(logical_cpus))

    # Set virtual_cpus
    VIRTUAL_CPUS = re.match(r'^BBB[a-zA-Z].+Online\sVirtual\sCPUs.+:\s([0-9]+)\"\n', line)
    if VIRTUAL_CPUS:
        virtual_cpus = VIRTUAL_CPUS.group(1)
        logging.info("virtual_cpus:" + str(virtual_cpus))

    # Identify Linux hosts
    OStype_Linux = re.search(r'AAA,OS,Linux', line)
    if OStype_Linux:
        OStype = "Linux"

    # Identify Solaris hosts
    OStype_Solaris = re.match(r'^AAA,OS,Solaris,.+', line)
    if OStype_Solaris:
        OStype = "Solaris"

    # Identify AIX hosts
    AIX_LEVEL_match = re.match(r'^AAA,AIX,(.+)', line)
    if AIX_LEVEL_match:
        OStype = "AIX"

# Show NMON OStype
logging.info("NMON OStype:" + str(OStype))

# If HOSTNAME could not be defined
if HOSTNAME == '-1':
    logging.error("ERROR: The hostname could not be extracted from Nmon data !")
    sys.exit(1)

# If DATE could not be defined
if DATE == '-1':
    logging.error("date could not be extracted from Nmon data !")
    sys.exit(1)

# If TIME could not be defined
if TIME == '-1':
    logging.error("time could not be extracted from Nmon data !")
    sys.exit(1)

# If logical_cpus could not be defined
if logical_cpus == '-1':
    logging.error("The number of logical cpus (logical_cpus) could not be extracted from Nmon data !")
    sys.exit(1)

# If virtual_cpus could not be defined, set it equal to logical_cpus
if virtual_cpus == '-1':
    virtual_cpus = logical_cpus
    logging.info("virtual_cpus: " + str(virtual_cpus))

# If SN could not be defined, not an AIX host, SN == HOSTNAME
if SN == '-1':
    SN = HOSTNAME

# Finally set the frameID equal to SN
frameID = SN

###############################
# NMON Structure Verification #
###############################

# The purpose of this section is to achieve some structure verification of the Nmon file
# to prevent data inconsistency

for line in data:

    # Verify we do not have any line that contain ZZZZ without beginning the line by ZZZZ
    # In such case, the nmon data is bad and buggy, converting it would generate data inconsistency

    # Search for ZZZZ truncated lines (eg. line containing ZZZZ pattern BUT not beginning the line)

    ZZZZ_truncated = re.match(r'.+ZZZZ,', line)
    if ZZZZ_truncated:
        # We do not use logging to be able to access this messages within Splunk (Splunk won't index error
        #  logging messages)

        msg = 'ERROR: hostname: ' + HOSTNAME + ' Detected Bad Nmon structure, found ZZZZ lines truncated! ' \
                                               '(ZZZZ lines contains the event timestamp and should always ' \
                                               'begin the line)'
        logging.info(msg)
        msg = 'ERROR: hostname: ' + HOSTNAME + ' Ignoring nmon data'
        logging.info(msg)
        sys.exit(1)

    # Search for old time format (eg. Nmon version V9 and prior)
    time_oldformat = re.match(r'(AAA,date,)([0-9]+)/([0-9]+)/([0-9]+)', line)
    if time_oldformat:
        msg = 'INFO: hostname: ' + HOSTNAME + ' Detected old Nmon version using old Date format (dd/mm/yy)'
        logging.info(msg)

        day = time_oldformat.group(2)
        month = time_oldformat.group(3)
        year = time_oldformat.group(4)

        # Convert %y to %Y
        year = datetime.datetime.strptime(year, '%y').strftime('%Y')

        # Convert from months numbers to months name for compatibility with later Nmon versions
        # Note: we won't use here datetime to avoid issues with locale names of months

        month = numbertomonth(month)

        DATE = day + '-' + month + '-' + year

        msg = 'INFO: hostname: ' + HOSTNAME + ' Date converted to: ' + DATE
        logging.info(msg)

# End for

################################
# Data status store #
################################

# Various status are stored in different files
# This includes the id check file, the config check file and status per section containing last epochtime proceeded
# These items will be stored in a per host dedicated directory

# create a directory under APP_VAR
# This directory will used to store per section last epochtime status
if is_windows:
    HOSTNAME_VAR = APP_VAR + '\\' + HOSTNAME + '_' + SN
else:
    HOSTNAME_VAR = APP_VAR + '/' + HOSTNAME + '_' + SN

if not os.path.isdir(HOSTNAME_VAR):
    try:
        os.mkdir(HOSTNAME_VAR)
    except Exception, e:
        msg = 'Error encountered during directory creation has failed due to:'
        msg = (msg, '%s' % e.__class__)
        logging.error(msg)

###############
# ID Check #
###############

# This section prevents Splunk from generating duplicated data for the same Nmon file
# While using the archive mode, Splunk may opens twice the same file sequentially
# If the Nmon file id is already present in our reference file, then we have already proceeded this Nmon and
# nothing has to be done
# Last execution result will be extracted from it to stdout

# Set default value for the last known epochtime
last_known_epochtime = 0

# Set the value in epochtime of the starting nmon
NMON_DATE = DATE + ' ' + TIME

# For Nmon V10 and more
timestamp_match = re.match(r'\d*-\w*-\w*\s\d*:\d*:\d*', NMON_DATE)
if timestamp_match:

    if is_windows:
        starting_epochtime = time.mktime(time.strptime(NMON_DATE, '%d-%b-%Y %H:%M:%S'))
    else:
        starting_epochtime = datetime.datetime.strptime(NMON_DATE, '%d-%b-%Y %H:%M:%S').strftime('%s')
    starting_time = datetime.datetime.strptime(NMON_DATE, '%d-%b-%Y %H:%M:%S').strftime('%d-%m-%Y %H:%M:%S')

else:
    # For Nmon v9 and prior

    if is_windows:
        starting_epochtime = time.mktime(time.strptime(NMON_DATE, '%d-%b-%Y %H:%M.%S'))
    else:
        starting_epochtime = datetime.datetime.strptime(NMON_DATE, '%d-%b-%Y %H:%M.%S').strftime('%s')

    starting_time = datetime.datetime.strptime(NMON_DATE, '%d-%b-%Y %H:%M.%S').strftime('%d-%m-%Y %H:%M:%S')

# Search for last epochtime in data
for line in data:

    # Extract timestamp

    # Nmon V9 and prior do not have date in ZZZZ
    # If unavailable, we'll use the global date (AAA,date)
    ZZZZ_DATE = '-1'
    ZZZZ_TIME = '-1'

    # For Nmon V10 and more

    timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
    if timestamp_match:
        ZZZZ_TIME = timestamp_match.group(2)
        ZZZZ_DATE = timestamp_match.group(3)

        # Replace month names with numbers
        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

        # Compose final timestamp
        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

        # Convert in epochtime
        if is_windows:
            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
        else:
            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').strftime('%s')

    # For Nmon V9 and less

    if ZZZZ_DATE == '-1':
        ZZZZ_DATE = DATE

        # Replace month names with numbers
        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

        timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)
        if timestamp_match:
            ZZZZ_TIME = timestamp_match.group(2)
            ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

            # Convert in epochtime
            if is_windows:
                ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
            else:
                ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').strftime('%s')

# Set ending epochtime
# noinspection PyBroadException
try:
    if ZZZZ_epochtime:
        ending_epochtime = ZZZZ_epochtime
    else:
        ZZZZ_epochtime = starting_epochtime
except NameError:
    logging.error("Encountered an Unexpected error while trying to analyse the ending period of this Nmon"
                  " file, cannot continue.")
    sys.exit(1)
except:
    logging.error("Encountered an Unexpected error while parsing this Nmon file Nmon, cannot continue")
    sys.exit(1)

# Evaluate if we are dealing with real time data or cold data
# This feature can be overriden by the --mode option
# Windows guest is not concerned
if options.mode == 'colddata':
    colddata = True
elif options.mode == 'realtime':
    realtime = True
elif is_windows:
    colddata = True
else:
    # options.mode is 'auto', therefore:
    # Evaluate if we are dealing with real time data or cold data
    if (int(start_time) - (4 * int(INTERVAL))) > int(ending_epochtime):
        colddata = True
    else:
        realtime = True

if realtime:
    # Override ID_REF & CONFIG_REF
    if is_windows:
        ID_REF = HOSTNAME_VAR + '\\' + HOSTNAME + '.id_reference_realtime.txt'
        CONFIG_REF = HOSTNAME_VAR + '\\' + HOSTNAME + '.config_reference_realtime.txt'
        BBB_FLAG = HOSTNAME_VAR + '\\' + HOSTNAME + '.BBB_status.flag'
    else:
        ID_REF = HOSTNAME_VAR + '/' + HOSTNAME + '.id_reference_realtime.txt'
        CONFIG_REF = HOSTNAME_VAR + '/' + HOSTNAME + '.config_reference_realtime.txt'
        BBB_FLAG = HOSTNAME_VAR + '/' + HOSTNAME + '.BBB_status.flag'
else:
    # Override ID_REF & CONFIG_REF
    if is_windows:
        ID_REF = HOSTNAME_VAR + '\\' + HOSTNAME + '.id_reference.txt'
        CONFIG_REF = HOSTNAME_VAR + '\\' + HOSTNAME + '.config_reference.txt'
        BBB_FLAG = HOSTNAME_VAR + '\\' + HOSTNAME + '.BBB_status.flag'
    else:
        ID_REF = HOSTNAME_VAR + '/' + HOSTNAME + '.id_reference.txt'
        CONFIG_REF = HOSTNAME_VAR + '/' + HOSTNAME + '.config_reference.txt'
        BBB_FLAG = HOSTNAME_VAR + '/' + HOSTNAME + '.BBB_status.flag'

# NMON file id (concatenation of ids)
idnmon = DATE + ':' + TIME + ',' + HOSTNAME + ',' + SN + ',' + str(bytes_total) + ',' + str(starting_epochtime) + ',' +\
         str(ending_epochtime)

# Partial idnmon that won't contain ending_epochtime for compare operation, to used for cold data
partial_idnmon = DATE + ':' + TIME + ',' + HOSTNAME + ',' + SN + ',' + str(bytes_total) + ',' + str(starting_epochtime)

# Show Nmon ID
logging.info("NMON ID:" + str(idnmon))

# Show real time / cold data message
if realtime:
    if options.mode == 'realtime':
        msg = "ANALYSIS: Enforcing realtime mode using --mode option"
    else:
        msg = 'ANALYSIS: Assuming Nmon realtime data'
    logging.info(msg)
elif colddata:
    if options.mode == 'colddata':
        msg = "ANALYSIS: Enforcing colddata mode using --mode option"
    else:
        msg = 'ANALYSIS: Assuming Nmon cold data'
    logging.info(msg)

# Open reference file for reading, if exists already
if os.path.isfile(ID_REF):

    with open(ID_REF, "r") as ref:

        for line in ref:

            if realtime:

                # Search for this ID
                idmatch = re.match(idnmon, line)
                if idmatch:

                    # If ID matches, then the file has been previously proceeded, let's show last result of execution
                    logging.info("This nmon file has been already processed, nothing to do.")
                    sys.exit(0)

                # If id does not match, recover the last known ending epoch time to proceed only new data
                else:

                    last_known_epochtime_match = re.match(r'.*Ending_epochtime:\s(\d+)', line)
                    if last_known_epochtime_match:
                        last_known_epochtime = last_known_epochtime_match.group(1)

            elif colddata:

                # Search for this ID
                idmatch = re.match(partial_idnmon, line)
                if idmatch:

                    # If ID matches, then the file has been previously proceeded, let's show last result of execution
                    logging.info("This nmon file has been already processed, nothing to do.")
                    sys.exit(0)

                # If id does not match, recover the last known ending epoch time to proceed only new data
                else:
                    last_known_epochtime = starting_epochtime

# If we here, then this file has not been previously proceeded

# Open reference file for writing
msg = now + " Reading NMON data: " + str(nbr_lines) + " lines" + " " + str(bytes_total) + " bytes"
openRef()

# write id
ref.write(msg + '\n')
ref.write(idnmon + '\n')

# write starting epoch
msg = "Starting_epochtime: " + str(starting_epochtime)
logging.info(msg)
ref.write(msg + '\n')

# write last epochtime of Nmon data
msg = "Ending_epochtime: " + str(ZZZZ_epochtime)
logging.info(msg)
ref.write(msg + '\n')

# Show and save last known epoch time
msg = 'last known epoch time: ' + str(last_known_epochtime)
logging.info(msg)
ref.write(msg + '\n')

# Set last known epochtime equal to starting epochtime if the nmon has not been yet proceeded
if last_known_epochtime == 0:
    last_known_epochtime = starting_epochtime

####################
# Write CONFIG csv #
####################

# Extraction of the AAA and BBB sections with a supplementary header to allow Splunk identifying the host and
# timestamp as a multi-lines event
# In any case, the Configuration extraction will not be executed more than once per hour
# In the case of Real Time data, the extraction will only be achieved once per Nmon file

# Update 04/17/2015: In real time mode with very large system, the performance collect may starts before the
# configuration ends (eg. an AAA section, followed by Perf metrics and later the BBB section)
# This would implies partial configuration extraction to be proceeded
# The script now verifies that the BBB section has been successfully extracted before setting the status to
# do not extract

# Set section
section = "CONFIG"

# Set output file
config_output = CONFIG_DIR + 'nmon_configdata.log'

# Set default for config_run:
# 0 --> Extract configuration
# 1 --> Don't Extract configuration
# default is extract
config_run = 0

# Search in ID_REF for a last matching execution
if os.path.isfile(CONFIG_REF):

    with open(CONFIG_REF, "rb") as f:

        for line in f:

            # Only proceed if hostname has the same value
            if HOSTNAME in line:

                CONFIG_REFDETAILS = re.match(r'^.+:\s(\d+)', line)
                config_lastepoch = CONFIG_REFDETAILS.group(1)

                if config_lastepoch:

                    time_delta = (int(now_epoch) - int(config_lastepoch))

                    if time_delta < 3600:

                        # Only set the status to do not extract is the BBB_FLAG is not present
                        if not os.path.isfile(BBB_FLAG):
                            config_run = 1
                        else:
                            config_run = 0

                    elif time_delta > 3600:

                        config_run = 0

if config_run == 0:

    if realtime:

        # Only allow one extraction of the config section per nmon file
        limit = (int(starting_epochtime) + (4 * int(INTERVAL)))

        if int(last_known_epochtime) < int(limit):

            msg = "CONFIG section will be extracted"
            logging.info(msg)
            ref.write(msg + "\n")

            # Initialize BBB_count
            BBB_count = 0

            # Open config output for writing
            with open(config_output, "ab") as config:

                # counter
                count = 0

                # Write header
                if kvdelim:
                    config.write('timestamp="' + now_epoch + '", ' + 'date="' + DATE + ':' + TIME + '", ' + 'host="' +
                             HOSTNAME + '", ' + 'serialnum="' + SN + '", configuration_content="' + '\n')
                else:
                    config.write('timestamp="' + now_epoch + '", ' + 'date="' + DATE + ':' + TIME + '", ' + 'host="' +
                             HOSTNAME + '", ' + 'serialnum="' + SN + '", configuration_content=' + '\n')

                for line in data:

                    # Extract AAA and BBB sections, and write to config output
                    AAABBB = re.match(r'^[AAA|BBB].+', line)

                    if AAABBB:
                        # Increment
                        count += 1

                        # Increment the BBB counter
                        if "BBB" in line:
                            BBB_count += 1

                        # Write
                        config.write(line)
                if kvdelim:
                    config.write('", data="nmon_configuration"')
                else:
                    config.write(', data="nmon_configuration"')

                # Under 10 lines of data in BBB, estimate extraction is not complete
                if BBB_count < 10:
                    with open(BBB_FLAG, "wb") as bbb_flag:
                        bbb_flag.write("BBB_status KO")
                else:
                    if os.path.isfile(BBB_FLAG):
                        os.remove(BBB_FLAG)

                # Show number of lines extracted
                result = "CONFIG section: Wrote" + " " + str(count) + " lines"
                logging.info(result)
                ref.write(result + '\n')

                # Save the a combo of HOSTNAME: current_epochtime in CONFIG_REF
                with open(CONFIG_REF, "wb") as f:
                    f.write(HOSTNAME + ": " + now_epoch + "\n")

        else:

            msg = "CONFIG section: Assuming we already extracted for this file"
            logging.info(msg)
            ref.write(msg + "\n")

    elif colddata:

        msg = "CONFIG section will be extracted"
        logging.info(msg)
        ref.write(msg + "\n")

        # Open config output for writing
        with open(config_output, "ab") as config:

            # counter
            count = 0

            # write header
            config.write('CONFIG' + ',' + DATE + ':' + TIME + ',' + HOSTNAME + ',' + SN + '\n')

            for line in data:

                # Extract AAA and BBB sections, and write to config output
                AAABBB = re.match(r'^[AAA|BBB].+', line)

                if AAABBB:
                    # Increment
                    count += 1

                    # Write
                    config.write(line)

            # Show number of lines extracted
            result = "CONFIG section: Wrote" + " " + str(count) + " lines"
            logging.info(result)
            ref.write(result + '\n')

            # Save the a combo of HOSTNAME: current_epochtime in CONFIG_REF
            with open(CONFIG_REF, "wb") as f:
                f.write(HOSTNAME + ": " + str(now_epoch) + "\n")

elif config_run == 1:
    # Show number of lines extracted
    result = "CONFIG section: will not be extracted (time delta of " + str(time_delta) +\
             " seconds is inferior to 1 hour)"
    logging.info(result)
    ref.write(result + '\n')

##########################
# Write PERFORMANCE DATA #
##########################

###################
# Static Sections : Header is dynamic but no devices context (drives, interfaces...) and there is
# no need to transpose the data
###################


def standard_section_fn(section):


    # Set output file
    currsection_output = DATA_DIR + 'nmon_perfdata.log'

    # Store last epochtime if in real time mode
    keyref = HOSTNAME_VAR + '/' + HOSTNAME + '.' + section + '_lastepoch.txt'

    if realtime:
        if not os.path.exists(keyref):
            if debug:
                logging.info("DEBUG, no keyref file for this " + str(section) +
                       " section (searched for " + str(keyref) + "), no data or first execution")
        else:
            with open(keyref, "r") as f:
                for line in f:
                    myregex = 'last_epoch:\s(\d+)'
                    myregex_match = re.search(myregex, line)

                    # Standard header extraction
                    if myregex_match:
                        last_epoch_persection = myregex_match.group(1)

                        if debug:
                            logging.info("DEBUG, Last known timestamp for " + str(section) +
                                  " section is " + str(last_epoch_persection))

        # In realtime mode, in case no per section information is available, let's use global epoch time
        try:
            last_epoch_persection
        except NameError:
            if debug:
                logging.debug("DEBUG: no last epoch information were found for " +str(section) +
                       " , using global last epoch time (gaps in data may occur if not the first time we run)")
            last_epoch_filter = last_known_epochtime
        else:
            if debug:
                logging.debug("DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur)")
            last_epoch_filter = last_epoch_persection

    # counter
    count = 0

    # sanity_check
    sanity_check = 1

    # Initialize num_cols_header to 0 (see sanity_check)
    num_cols_header = 0

    # Sequence to search for
    seq = str(section) + ',' + 'T'

    for line in data:

        # Extract sections
        if str(seq) in line:  # Don't use regex here for more performance

            # increment
            count += 1

    # Virtually always activates CPUnn
    if section == 'CPUnn':
        # increment
        count += 1

    if count >= 1:

        # Open StringIO for temp in memory
        membuffer = cStringIO.StringIO()

        # Open output for writing
        with open(currsection_output, "ab") as currsection:

            # counter
            count = 0

            for line in data:

                # Extract sections (manage specific case of CPUnn), and write to output
                if section == "CPUnn":
                    myregex = r'^' + 'CPU\d*' + '|ZZZZ.+'
                else:
                    myregex = r'^' + section + '|ZZZZ.+'

                find_section = re.match(myregex, line)
                if find_section:

                    # Replace trouble strings
                    line = subpctreplace(line)
                    line = subreplace(line)

                    # csv header

                    # Extract header excluding data that always has Txxxx for timestamp reference
                    # For CPUnn, search for first core
                    if section == "CPUnn":
                        myregex = '(' + 'CPU01' + ')\,([^T].+)'
                    else:
                        myregex = '(' + section + ')\,([^T].+)'

                    # Search for header
                    fullheader_match = re.search(myregex, line)

                    # Standard header extraction

                    # For CPUnn, if first core were not found using CPU01, search for CPU000 (Solaris) and
                    # CPU001 (Linux)
                    if section == "CPUnn":
                        if not fullheader_match:
                            myregex = '(' + 'CPU000' + ')\,([^T].+)'
                            fullheader_match = re.search(myregex, line)

                        if not fullheader_match:
                            myregex = '(' + 'CPU001' + ')\,([^T].+)'
                            fullheader_match = re.search(myregex, line)

                    if fullheader_match:
                        fullheader = fullheader_match.group(2)

                        # Replace "." by "_" only for header
                        fullheader = re.sub("\.", '_', fullheader)

                        # Replace any blank space before comma only for header
                        fullheader = re.sub(", ", ',', fullheader)

                        header_match = re.search(r'([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9,]*)', fullheader)

                        if header_match:
                            header = header_match.group(2)

                            # increment
                            count += 1

                            # Write header
                            final_header = 'timestamp' + ',' + 'OStype' + ',' + 'type' + ',' + 'hostname' + ',' +\
                                           'serialnum' + ',' + 'logical_cpus' + ',' + 'virtual_cpus' + ',' + 'ZZZZ' +\
                                           ',' + 'interval' + ',' + 'snapshots' + ',' + header + '\n'

                            # Number of separators in final header
                            num_cols_header = final_header.count(',')

                            # Write header
                            membuffer.write(final_header)

                    # Old Nmon version sometimes incorporates a Txxxx reference in the header, this is unclean
                    # but we want to try getting the header anyway

                    elif not fullheader_match:
                        # Assume the header may start with Txxx, then 1 non alpha char
                        myregex = '(' + section + ')\,(T\d+),([a-zA-Z]+.+)'
                        fullheader_match = re.search(myregex, line)

                        if fullheader_match:
                            fullheader = fullheader_match.group(3)

                            # Replace "." by "_" only for header
                            fullheader = re.sub("\.", '_', fullheader)

                            # Replace any blank space before comma only for header
                            fullheader = re.sub(", ", ',', fullheader)

                            header_match = re.search(r'([a-zA-Z\-/_0-9,]*)', fullheader)

                            if header_match:
                                header = header_match.group(1)

                                # increment
                                count += 1

                                # Write header
                                final_header = 'timestamp' + ',' + 'OStype' + ',' + 'type' + ',' + 'hostname' + ',' +\
                                               'serialnum' + ','  + 'logical_cpus' + ',' + 'virtual_cpus' + ',' +\
                                               'ZZZZ' + ',' + 'interval' + ',' + 'snapshots' + ',' + header + '\n'

                                # Number of separators in final header
                                num_cols_header = final_header.count(',')

                                # Write header
                                membuffer.write(final_header)

                    # Extract timestamp

                    # Nmon V9 and prior do not have date in ZZZZ
                    # If unavailable, we'll use the global date (AAA,date)
                    ZZZZ_DATE = '-1'
                    ZZZZ_TIME = '-1'

                    # For Nmon V10 and more

                    timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
                    if timestamp_match:
                        ZZZZ_TIME = timestamp_match.group(2)
                        ZZZZ_DATE = timestamp_match.group(3)

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        # Compose final timestamp
                        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                        if is_windows:
                            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                        else:
                            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                .strftime('%s')

                    # For Nmon V9 and less

                    if ZZZZ_DATE == '-1':
                        ZZZZ_DATE = DATE

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)
                        if timestamp_match:
                            ZZZZ_TIME = timestamp_match.group(2)
                            ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                            if is_windows:
                                ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                            else:
                                ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                    .strftime('%s')

                    # Extract Data
                    if section == "CPUnn":
                        myregex = r'^' + '(CPU\d*)' + '\,(T\d+)\,(.+)\n'
                    else:
                        myregex = r'^' + section + '\,(T\d+)\,(.+)\n'
                    perfdata_match = re.match(myregex, line)

                    if perfdata_match:
                        if section == 'CPUnn':
                            perfdatatype = perfdata_match.group(1)
                            perfdata = perfdata_match.group(3)
                        else:
                            perfdata = perfdata_match.group(2)

                        if realtime:

                            if ZZZZ_epochtime > last_epoch_filter:

                                # increment
                                count += 1

                                # final_perfdata
                                if section == 'CPUnn':

                                    final_perfdata = ZZZZ_epochtime + ',' + OStype + ',' + perfdatatype + ',' + SN +\
                                                     ',' + HOSTNAME + ',' + logical_cpus + ',' + virtual_cpus + ',' +\
                                                     ZZZZ_timestamp + ',' + INTERVAL + ',' + SNAPSHOTS + ',' +\
                                                     perfdata + '\n'
                                else:
                                    final_perfdata = ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN +\
                                                     ',' + HOSTNAME + ',' + logical_cpus + ',' + virtual_cpus + ',' +\
                                                     ZZZZ_timestamp + ',' + INTERVAL + ',' + SNAPSHOTS + ',' +\
                                                     perfdata + '\n'

                                # Analyse the first line of data: Compare number of fields in data with number of fields
                                # in header
                                # If the number of fields is higher than header, we assume this section is not
                                # consistent and will be entirely dropped
                                # This happens in rare times (mainly with old buggy nmon version) that the header is bad
                                # formatted (for example missing comma between fields identification)
                                # For performance purposes, we will test this only with first line of data and assume
                                # the data sanity based on this result
                                if count == 2:

                                    # Number of separators in final header
                                    num_cols_perfdata = final_perfdata.count(',')

                                    if num_cols_perfdata > num_cols_header:

                                        msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                              ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                              ' fields in data, ' + str(num_cols_header) \
                                              + ' fields in header, extra fields detected (more fields in data ' \
                                                'than header), dropping this section to prevent data inconsistency'
                                        logging.error(msg)
                                        ref.write(msg + "\n")

                                        # Affect a sanity check to 1, bad data
                                        sanity_check = 1

                                    else:

                                        # Affect a sanity check to 0, good data
                                        sanity_check = 0

                                # Write perf data
                                membuffer.write(final_perfdata)
                            else:
                                if debug:
                                    logging.debug("DEBUG, " + str(section) + " ignoring event " + str(ZZZZ_timestamp) +
                                    " ( " + str(ZZZZ_epochtime) + " is lower than last known epoch time for this "
                                                                  "section " + str(last_epoch_filter) + " )")

                        elif colddata:

                            # increment
                            count += 1

                            # final_perfdata
                            if section == 'CPUnn':
                                final_perfdata = ZZZZ_epochtime + ',' + OStype + ',' + perfdatatype + ',' + SN +\
                                                 ',' + HOSTNAME + ',' + logical_cpus + ',' + virtual_cpus + ',' +\
                                                 ZZZZ_timestamp + ',' + INTERVAL + ',' + SNAPSHOTS + ',' +\
                                                 perfdata + '\n'
                            else:
                                final_perfdata = ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN +\
                                                 ',' + HOSTNAME + ',' + logical_cpus + ',' + virtual_cpus + ',' +\
                                                 ZZZZ_timestamp + ',' + INTERVAL + ',' + SNAPSHOTS + ',' +\
                                                 perfdata + '\n'

                            # Analyse the first line of data: Compare number of fields in data with number of fields
                            # in header
                            # If the number of fields is higher than header, we assume this section is not consistent
                            # and will be entirely dropped
                            # This happens in rare times (mainly with old buggy nmon version) that the header is bad
                            # formatted (for example missing comma between fields identification)
                            # For performance purposes, we will test this only with first line of data and assume the
                            # data sanity based on this result
                            if count == 2:

                                # Number of separators in final header
                                num_cols_perfdata = final_perfdata.count(',')

                                if num_cols_perfdata > num_cols_header:

                                    msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                          ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                          ' fields in data, ' + str(num_cols_header) \
                                          + ' fields in header, extra fields detected (more fields in data ' \
                                            'than header), dropping this section to prevent data inconsistency'
                                    logging.error(msg)
                                    ref.write(msg + "\n")

                                    # Affect a sanity check to 1, bad data
                                    sanity_check = 1

                                else:

                                    # Affect a sanity check to 0, good data
                                    sanity_check = 0

                            # Write perf data
                            membuffer.write(final_perfdata)

        # Rewind temp
        membuffer.seek(0)

        # Write final kv file in append mode
        write_kv(membuffer, currsection_output)

        # Show number of lines extracted
        result = section + " section: Wrote" + " " + str(count) + " lines"
        logging.info(result)
        ref.write(result + "\n")

        # In realtime, Store last epoch time for this section
        if realtime:
            with open(keyref, "wb") as f:
                f.write("last_epoch: " + ZZZZ_epochtime + "\n")

    # End for


# These are standard static sections common for all OS
for section in static_section:
    standard_section_fn(section)

# These are AIX specific static sections, search for this only if Nmon file comes from AIX, or if the OStype
# couldn't be identified
if OStype in ("AIX", "Unknown"):
    for section in AIX_static_section:
        standard_section_fn(section)

# Solaris specific
if OStype in ("Solaris", "Unknown"):
    for section in Solaris_static_section:
        standard_section_fn(section)

###################
# TOP section: has a specific structure with uncommon fields, needs to be treated separately
###################


def top_section_fn(section):

    # Set output file
    currsection_output = DATA_DIR + 'nmon_perfdata.log'

    # Store last epochtime if in real time mode
    keyref = HOSTNAME_VAR + '/' + HOSTNAME + '.' + section + '_lastepoch.txt'

    if realtime:
        if not os.path.exists(keyref):
            if debug:
                logging.debug("DEBUG, no keyref file for this " + str(section) +
                       " section (searched for " + str(keyref) + "), no data or first execution")
        else:
            with open(keyref, "r") as f:
                for line in f:
                    myregex = 'last_epoch:\s(\d+)'
                    myregex_match = re.search(myregex, line)

                    # Standard header extraction
                    if myregex_match:
                        last_epoch_persection = myregex_match.group(1)

                        if debug:
                            logging.debug("DEBUG, Last known timestamp for " + str(section) +
                                  " section is " + str(last_epoch_persection))

        # In realtime mode, in case no per section information is available, let's use global epoch time
        try:
            last_epoch_persection
        except NameError:
            if debug:
                logging.debug("DEBUG: no last epoch information were found for " + str(section) +
                       " , using global last epoch time (gaps in data may occur if not the first time we run)")
            last_epoch_filter = last_known_epochtime
        else:
            if debug:
                logging.debug("DEBUG: Using per section last epoch time for event filtering (no gaps in data "
                              "should occur)")
            last_epoch_filter = last_epoch_persection

    # counter
    count = 0

    # Sequence to search for
    seq = str(section) + ','

    for line in data:

        # Extract sections
        if str(seq) in line:  # Don't use regex here for more performance

            # increment
            count += 1

    if count >= 1:

        # Open StringIO for temp in memory
        membuffer = cStringIO.StringIO()

        # Open output for writing
        with open(currsection_output, "ab") as currsection:

            # counter
            count = 0

            for line in data:

                # Extract sections, and write to output
                myregex = r'^' + 'TOP,.PID' + '|ZZZZ.+'
                find_section = re.match(myregex, line)
                if find_section:

                    line = subpcttopreplace(line)
                    line = subreplace(line)

                    # csv header

                    # Extract header excluding data that always has Txxxx for timestamp reference
                    myregex = '(' + section + ')\,([^T].+)'
                    fullheader_match = re.search(myregex, line)

                    if fullheader_match:
                        fullheader = fullheader_match.group(2)

                        # Replace "." by "_" only for header
                        fullheader = re.sub("\.", '_', fullheader)

                        # Replace any blank space before comma only for header
                        fullheader = re.sub(", ", ',', fullheader)

                        header_match = re.search(r'([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9,]*)',
                                                 fullheader)

                        if header_match:
                            header_part1 = header_match.group(1)
                            header_part2 = header_match.group(3)
                            header = header_part1 + header_part2

                            # increment
                            count += 1

                            # Write header
                            membuffer.write(
                                'timestamp' + ',' + 'OStype' + ',' + 'type' + ',' + 'serialnum' + ',' + 'hostname' +
                                ',' + 'logical_cpus' + ',' + 'virtual_cpus' + ',' + 'ZZZZ' + ',' + 'interval' + ',' +
                                'snapshots' + ',' + header + '\n'),

                    # Extract timestamp

                    # Nmon V9 and prior do not have date in ZZZZ
                    # If unavailable, we'll use the global date (AAA,date)
                    ZZZZ_DATE = '-1'
                    ZZZZ_TIME = '-1'

                    # For Nmon V10 and more

                    timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
                    if timestamp_match:
                        ZZZZ_TIME = timestamp_match.group(2)
                        ZZZZ_DATE = timestamp_match.group(3)

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                        if is_windows:
                            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                        else:
                            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                .strftime('%s')

                    # For Nmon V9 and less

                    if ZZZZ_DATE == '-1':
                        ZZZZ_DATE = DATE
                        timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)

                        if timestamp_match:
                            ZZZZ_TIME = timestamp_match.group(2)

                            # Replace month names with numbers
                            ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                            ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME
                            if is_windows:
                                ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                            else:
                                ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                    .strftime('%s')

                # Extract Data
                perfdata_match = re.match('^TOP,([0-9]+),(T\d+),(.+)\n', line)
                if perfdata_match:
                    perfdata_part1 = perfdata_match.group(1)
                    perfdata_part2 = perfdata_match.group(3)
                    perfdata = perfdata_part1 + ',' + perfdata_part2

                    if realtime:

                        if ZZZZ_epochtime > last_epoch_filter:

                            # increment
                            count += 1

                            # Write perf data
                            membuffer.write(
                                ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME + ',' +
                                logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL + ',' +
                                SNAPSHOTS + ',' + perfdata + '\n'),
                        else:
                            if debug:
                                logging.debug("DEBUG, " + str(section) + " ignoring event " + str(ZZZZ_timestamp) +
                                       " ( " + str(ZZZZ_epochtime) + " is lower than last known epoch time for this"
                                                                " section " + str(last_epoch_filter) + " )")

                    elif colddata:

                        # increment
                        count += 1

                        # Write perf data
                        membuffer.write(
                            ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME + ',' +
                            logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL + ',' +
                            SNAPSHOTS + ',' + perfdata + '\n'),

        # Rewind temp
        membuffer.seek(0)

        # Write final kv file in append mode
        write_kv(membuffer, currsection_output)

        # Show number of lines extracted
        result = section + " section: Wrote" + " " + str(count) + " lines"
        logging.info(result)
        ref.write(result + "\n")

        # In realtime, Store last epoch time for this section
        if realtime:
            with open(keyref, "wb") as f:
                f.write("last_epoch: " + ZZZZ_epochtime + "\n")

# End for

# Run
for section in top_section:

    top_section_fn(section)

###################
# UARG section: has a specific structure with uncommon fields, needs to be treated separately
###################

# Note: UARG is not continuously collected as progs arguments may not always change (mainly for real time)
# For this section specifically write from membuffer only

# UARG is applicable only for AIX and Linux hosts


def uarg_section_fn(section):

    # Set output file
    currsection_output = DATA_DIR + 'nmon_perfdata.log'

    # Store last epochtime if in real time mode
    keyref = HOSTNAME_VAR + '/' + HOSTNAME + '.' + section + '_lastepoch.txt'

    if realtime:
        if not os.path.exists(keyref):
            if debug:
                logging.debug("DEBUG, no keyref file for this " + str(section) +
                       " section (searched for " + str(keyref) + "), no data or first execution")
        else:
            with open(keyref, "r") as f:
                for line in f:
                    myregex = 'last_epoch:\s(\d+)'
                    myregex_match = re.search(myregex, line)

                    # Standard header extraction
                    if myregex_match:
                        last_epoch_persection = myregex_match.group(1)

                        if debug:
                            logging.debug("DEBUG, Last known timestamp for " + str(section) +
                                  " section is " + str(last_epoch_persection))

        # In realtime mode, in case no per section information is available, let's use global epoch time
        try:
            last_epoch_persection
        except NameError:
            if debug:
                logging.debug("DEBUG: no last epoch information were found for " + str(section) +
                       " , using global last epoch time (gaps in data may occur if not the first time we run)")
            last_epoch_filter = last_known_epochtime
        else:
            if debug:
                logging.debug("DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur)")
            last_epoch_filter = last_epoch_persection

    # counter
    count = 0

    # set oslevel default
    oslevel = "Unknown"

    # Sequence to search for
    seq = str(section) + ','

    for line in data:

        # Extract sections
        if str(seq) in line:  # Don't use regex here for more performance

            # increment
            count += 1

    if count >= 1:

        # Open StringIO for temp in memory
        membuffer = cStringIO.StringIO()

        # counter
        count = 0

        for line in data:

            # Extract sections, and write to output
            myregex = r'^' + 'UARG,.Time' + '|ZZZZ.+'
            find_section = re.match(myregex, line)
            if find_section:
                line = subpcttopreplace(line)
                line = subreplace(line)

                # csv header

                # Extract header excluding data that always has Txxxx for timestamp reference
                myregex = '(' + section + ')\,(.+)'
                fullheader_match = re.search(myregex, line)

                if fullheader_match:
                    fullheader = fullheader_match.group(2)

                    # Replace "." by "_" only for header
                    fullheader = re.sub("\.", '_', fullheader)

                    header_match = re.search(r'([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9,]*)',
                                             fullheader)

                    if header_match:
                        header_part1 = header_match.group(2)
                        header_part2 = header_match.group(3)
                        header = header_part1 + header_part2

                        # Specifically for UARG, set OS type based on header fields
                        os_match = re.search(r'PID,PPID,COMM,THCOUNT,USER,GROUP,FullCommand', header)

                        # Since V1.11, sarmon for Solaris implements UARG the same way Linux does
                        if os_match:
                            oslevel = 'AIX_or_Solaris'
                        else:
                            oslevel = 'Linux'

                        # increment
                        count += 1

                        # Write header
                        membuffer.write(
                            'timestamp' + ',' + 'OStype' + ',' + 'type' + ',' + 'serialnum' + ',' + 'hostname' +
                            ',' + 'logical_cpus' + ',' + 'virtual_cpus' + ',' + 'ZZZZ' + ',' + 'interval' +
                            ',' + 'snapshots' + ',' + header + '\n'),

                # Extract timestamp

                # Nmon V9 and prior do not have date in ZZZZ
                # If unavailable, we'll use the global date (AAA,date)
                ZZZZ_DATE = '-1'
                ZZZZ_TIME = '-1'

                # For Nmon V10 and more

                timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
                if timestamp_match:
                    ZZZZ_TIME = timestamp_match.group(2)
                    ZZZZ_DATE = timestamp_match.group(3)

                    # Replace month names with numbers
                    ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                    ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                    if is_windows:
                        ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                    else:
                        ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').strftime('%s')

                # For Nmon V9 and less

                if ZZZZ_DATE == '-1':
                    ZZZZ_DATE = DATE
                    timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)

                    if timestamp_match:
                        ZZZZ_TIME = timestamp_match.group(2)

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                        if is_windows:
                            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                        else:
                            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                .strftime('%s')

            if oslevel == 'Linux':  # Linux OS specific header

                # Extract Data
                perfdata_match = re.match('^UARG,T\d+,([0-9]*),([a-zA-Z\-/_:\.0-9]*),(.+)\n', line)

                if perfdata_match:
                    # In this section, we statically expect 3 fields: PID,ProgName,FullCommand
                    # The FullCommand may be very problematic as it may almost contain any kind of char, comma included
                    # Let's separate groups and insert " delimiter

                    perfdata_part1 = perfdata_match.group(1)
                    perfdata_part2 = perfdata_match.group(2)
                    perfdata_part3 = perfdata_match.group(3)
                    perfdata = perfdata_part1 + ',' + perfdata_part2 + ',"' + perfdata_part3 + '"'

                    if realtime:

                        if ZZZZ_epochtime > last_known_epochtime:

                            # increment
                            count += 1

                            # Write perf data
                            membuffer.write(
                                 ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME +
                                 ',' + logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL +
                                 ',' + SNAPSHOTS + ',' + perfdata + '\n'),

                    elif colddata:

                        # increment
                        count += 1

                        # Write perf data
                        membuffer.write(
                            ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME +
                            ',' + logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL +
                            ',' + SNAPSHOTS + ',' + perfdata + '\n'),

            if oslevel == 'AIX_or_Solaris':  # AIX and Solaris OS specific header

                # Extract Data
                perfdata_match = re.match(
                    '^UARG,T\d+,\s*([0-9]*)\s*,\s*([0-9]*)\s*,\s*([a-zA-Z-/_:\.0-9]*)\s*,\s*([0-9]*)\s*,\s*([a-zA-Z-/_:'
                    '\.0-9]*\s*),\s*([a-zA-Z-/_:\.0-9]*)\s*,(.+)\n',
                    line)

                if perfdata_match:
                    # In this section, we statically expect 7 fields: PID,PPID,COMM,THCOUNT,USER,GROUP,FullCommand
                    # The FullCommand may be very problematic as it may almost contain any kind of char, comma included
                    # This field will have " separator added

                    perfdata_part1 = perfdata_match.group(1)
                    perfdata_part2 = perfdata_match.group(2)
                    perfdata_part3 = perfdata_match.group(3)
                    perfdata_part4 = perfdata_match.group(4)
                    perfdata_part5 = perfdata_match.group(5)
                    perfdata_part6 = perfdata_match.group(6)
                    perfdata_part7 = perfdata_match.group(7)

                    perfdata = perfdata_part1 + ',' + perfdata_part2 + ',' + perfdata_part3 + ',' + perfdata_part4 +\
                               ',' + perfdata_part5 + ',' + perfdata_part6 + ',"' + perfdata_part7 + '"'

                    if realtime:

                        if ZZZZ_epochtime > last_epoch_filter:

                            # increment
                            count += 1

                            # Write perf data
                            membuffer.write(
                                ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME + ',' +
                                logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL + ',' +
                                SNAPSHOTS + ',' + perfdata + '\n'),
                        else:
                            if debug:
                                logging.debug("DEBUG, " + str(section) + " ignoring event " + str(ZZZZ_timestamp) +
                                " ( " + str(ZZZZ_epochtime) + " is lower than last known epoch time "
                                                        "for this section " + str(last_epoch_filter) + " )")

                    elif colddata:

                        # increment
                        count += 1

                        # Write perf data
                        membuffer.write(
                            ZZZZ_epochtime + ',' + OStype + ',' + section + ',' + SN + ',' + HOSTNAME + ',' +
                            logical_cpus + ',' + virtual_cpus + ',' + ZZZZ_timestamp + ',' + INTERVAL + ',' +
                            SNAPSHOTS + ',' + perfdata + '\n'),

        # Show number of lines extracted
        result = section + " section: Wrote" + " " + str(count) + " lines"
        logging.info(result)
        ref.write(result + "\n")

        # In realtime, Store last epoch time for this section
        if realtime:
            with open(keyref, "wb") as f:
                f.write("last_epoch: " + ZZZZ_epochtime + "\n")

        # Open output for writing
        with open(currsection_output, "ab") as currsection:

            # Rewind temp
            membuffer.seek(0)

            # Write final kv file in append mode
            write_kv(membuffer, currsection_output)

            # close membuffer
            membuffer.close()

# End for

if OStype in ('AIX', 'Linux', 'Solaris', 'Unknown'):
    for section in uarg_section:
        uarg_section_fn(section)

###################
# Dynamic Sections : data requires to be transposed to be exploitable within Splunk
###################


def dynamic_section_fn(section):

    # Set output file (will be opened for writing after data transposition)
    currsection_output = DATA_DIR + 'nmon_perfdata.log'

    # Sequence to search for
    seq = str(section) + ',' + 'T'

    # Store last epochtime if in real time mode
    keyref = HOSTNAME_VAR + '/' + HOSTNAME + '.' + section + '_lastepoch.txt'

    if realtime:
        if not os.path.exists(keyref):
            if debug:
                logging.debug("DEBUG, no keyref file for this " + str(section) +
                       " section (searched for " + str(keyref) + "), no data or first execution")
        else:
            with open(keyref, "r") as f:
                for line in f:
                    myregex = 'last_epoch:\s(\d+)'
                    myregex_match = re.search(myregex, line)

                    # Standard header extraction
                    if myregex_match:
                        last_epoch_persection = myregex_match.group(1)

                        if debug:
                            logging.debug("DEBUG, Last known timestamp for " + str(section) +
                                  " section is " + str(last_epoch_persection))

        # In realtime mode, in case no per section information is available, let's use global epoch time
        try:
            last_epoch_persection
        except NameError:
            if debug:
                logging.debug("DEBUG: no last epoch information were found for " + str(section) +
                       " , using global last epoch time (gaps in data may occur if not the first time we run)")
            last_epoch_filter = last_known_epochtime
        else:
            if debug:
                logging.debug("DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur)")
            last_epoch_filter = last_epoch_persection

    # counter
    count = 0

    # sanity_check
    sanity_check = 1

    # Initialize num_cols_header to 0 (see sanity_check)
    num_cols_header = 0

    for line in data:

        # Extract sections
        if str(seq) in line:  # Don't use regex here for more performance

            # increment
            count += 1

    if count >= 1:

        # Open StringIO for temp in memory
        membuffer = cStringIO.StringIO()

        # Here we need a second temp space
        membuffer2 = cStringIO.StringIO()

        # counter
        count = 0

        for line in data:

            # Extract sections, and write to output
            myregex = r'^' + section + '[0-9]*' + '|ZZZZ.+'
            find_section = re.match(myregex, line)

            if find_section:

                line = subpctreplace(line)
                line = subreplace(line)

                # csv header

                # Extract header excluding data that always has Txxxx for timestamp reference
                myregex = '(' + section + ')\,([^T].+)'
                fullheader_match = re.search(myregex, line)

                if fullheader_match:
                    fullheader = fullheader_match.group(2)

                    # Replace "." by "_" only for header
                    fullheader = re.sub("\.", '_', fullheader)

                    # Replace any blank space before comma only for header
                    fullheader = re.sub(", ", ',', fullheader)

                    # Remove any blank space still present in header
                    fullheader = re.sub(" ", '', fullheader)

                    header_match = re.match(r'([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9,]*)', fullheader)

                    if header_match:
                        header = header_match.group(2)

                        final_header = 'ZZZZ' + ',' + header + '\n'

                        # increment
                        count += 1

                        # Number of separators in final header
                        num_cols_header = final_header.count(',')

                        # Write header
                        membuffer.write(final_header),

                # Extract timestamp

                # Nmon V9 and prior do not have date in ZZZZ
                # If unavailable, we'll use the global date (AAA,date)
                ZZZZ_DATE = '-1'
                ZZZZ_TIME = '-1'

                # For Nmon V10 and more

                timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
                if timestamp_match:
                    ZZZZ_TIME = timestamp_match.group(2)
                    ZZZZ_DATE = timestamp_match.group(3)

                    # Replace month names with numbers
                    ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                    ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                    if is_windows:
                        ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                    else:
                        ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').strftime('%s')

                # For Nmon V9 and less

                if ZZZZ_DATE == '-1':
                    ZZZZ_DATE = DATE
                    timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)

                    if timestamp_match:
                        ZZZZ_TIME = timestamp_match.group(2)

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                        if is_windows:
                            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                        else:
                            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S')\
                                .strftime('%s')

                # Extract Data
                myregex = r'^' + section + '\,(T\d+)\,(.+)\n'
                perfdata_match = re.match(myregex, line)
                if perfdata_match:
                    perfdata = perfdata_match.group(2)

                    # final perfdata
                    final_perfdata = ZZZZ_timestamp + ',' + perfdata + '\n'

                    if realtime:

                        if ZZZZ_epochtime > last_epoch_filter:

                            # increment
                            count += 1

                            # Analyse the first line of data: Compare number of fields in data with number of fields
                            # in header
                            # If the number of fields is higher than header, we assume this section is not consistent
                            # and will be entirely dropped
                            # This happens in rare times (mainly with old buggy nmon version) that the header is bad
                            # formatted (for example missing comma between fields identification)
                            # For performance purposes, we will test this only with first line of data and assume
                            # the data sanity based on this result
                            if count == 2:

                                # Number of separators in final header
                                num_cols_perfdata = final_perfdata.count(',')

                                if num_cols_perfdata > num_cols_header:

                                    msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                          ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                          ' fields in data, ' + str(num_cols_header) +\
                                          ' fields in header, extra fields detected (more fields in data than header)' \
                                          ', dropping this section to prevent data inconsistency'
                                    logging.error(msg)
                                    ref.write(msg + "\n")

                                    if debug:
                                        logging.debug("\nDebug information: header content:\n")
                                        logging.debug(final_header)
                                        logging.debug("\nDebug information: data sample:\n")
                                        logging.debug(final_perfdata +"\n")

                                    # Affect a sanity check to 1, bad data
                                    sanity_check = 1

                                else:

                                    # Affect a sanity check to 0, good data
                                    sanity_check = 0

                            # Write perf data
                            membuffer.write(ZZZZ_timestamp + ',' + perfdata + '\n'),
                        else:
                            if debug:
                                logging.debug("DEBUG, " + str(section) + " ignoring event " + str(ZZZZ_timestamp) +
                                " ( " + str(ZZZZ_epochtime) + " is lower than last known epoch time for this section " +
                                       str(last_epoch_filter) + " )")

                    elif colddata:

                        # increment
                        count += 1

                        # Analyse the first line of data: Compare number of fields in data with number of fields
                        # in header
                        # If the number of fields is higher than header, we assume this section is not consistent and
                        # will be entirely dropped
                        # This happens in rare times (mainly with old buggy nmon version) that the header is bad
                        # formatted (for example missing comma between fields identification)
                        # For performance purposes, we will test this only with first line of data and assume the data
                        # sanity based on this result
                        if count == 2:

                            # Number of separators in final header
                            num_cols_perfdata = final_perfdata.count(',')

                            if num_cols_perfdata > num_cols_header:

                                msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                      ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                      ' fields in data, ' + str(num_cols_header) +\
                                      ' fields in header, extra fields detected (more fields in data than header),' \
                                      ' dropping this section to prevent data inconsistency'
                                logging.debug(msg)
                                ref.write(msg + "\n")

                                if debug:
                                    logging.debug("\nDebug information: header content:")
                                    logging.debug(final_header)
                                    logging.debug("Debug information: data sample:")
                                    logging.debug(final_perfdata)

                                # Affect a sanity check to 1, bad data
                                sanity_check = 1

                            else:

                                # Affect a sanity check to 0, good data
                                sanity_check = 0

                        # Write perf data
                        membuffer.write(ZZZZ_timestamp + ',' + perfdata + '\n'),

        if sanity_check == 0:

            # Reset counter
            count = 0

            # Open final for writing
            with open(currsection_output, "ab") as currsection:

                # Rewind temp
                membuffer.seek(0)

                # Write to second temp place
                writer = csv.writer(membuffer2)
                writer.writerow(
                    ['timestamp', 'OStype', 'type', 'serialnum', 'hostname', 'interval',
                     'snapshots', 'ZZZZ', 'device', 'value'])

                # increment
                count += 1

                for d in csv.DictReader(membuffer):
                    ZZZZ = d.pop('ZZZZ')
                    for device, value in sorted(d.items()):
                        # increment
                        count += 1

                        row = [ZZZZ_epochtime, OStype, section, SN, HOSTNAME, INTERVAL,
                               SNAPSHOTS, ZZZZ, device, value]
                        writer.writerow(row)

                        # End for

                # Rewind secondary temp
                membuffer2.seek(0)

                # Write final kv file in append mode
                write_kv(membuffer2, currsection_output)

            # Show number of lines extracted
            result = section + " section: Wrote" + " " + str(count) + " lines"
            logging.info(result)
            ref.write(result + "\n")

            # In realtime, Store last epoch time for this section
            if realtime:
                with open(keyref, "wb") as f:
                    f.write("last_epoch: " + ZZZZ_epochtime + "\n")

            # Discard memory membuffer
            membuffer.close()
            membuffer2.close()

        elif sanity_check == 0:

            # Discard memory membuffer
            membuffer.close()
            membuffer2.close()

            # End for

###################
# Disk* Dynamic Sections : data requires to be transposed to be exploitable within Splunk
###################

# Because Big systems can have a very large number of drives, Nmon create a new section for each step of 150 devices
# We allow up to 20 x 150 devices to be managed
# This will create a csv for each section (DISKBUSY, DISKBUSY1...), Splunk will manage this using a wildcard when
# searching for data
for section in dynamic_section1:
    dynamic_section_fn(section)

# Then proceed to sub section if any
for subsection in dynamic_section1:

    persubsection = [subsection + "1", subsection + "2", subsection + "3", subsection + "4", subsection + "5",
                  subsection + "6", subsection + "7", subsection + "8", subsection + "9", subsection + "10",
                  subsection + "11", subsection + "12", subsection + "13", subsection + "14", subsection + "15",
                  subsection + "17", subsection + "18", subsection + "19"]

    for section in persubsection:
        dynamic_section_fn(section)

###################
# Other Dynamic Sections : data requires to be transposed to be exploitable within Splunk
###################

for section in dynamic_section2:
    dynamic_section_fn(section)

###################
# AIX Only Dynamic Sections : data requires to be transposed to be exploitable within Splunk
###################

# Run
if OStype in ("AIX", "Unknown"):
    for section in AIX_dynamic_various:
        dynamic_section_fn(section)

###################
# Solaris Sections : data requires to be transposed to be exploitable within Splunk
###################

# Specially for WLM Solaris section, we will add the number of logical CPUs to allow evaluation of % CPU
# report in logical CPU


def solaris_wlm_section_fn(section):

    # Set output file (will be opened for writing after data transposition)
    currsection_output = DATA_DIR + 'nmon_perfdata.log'

    # Sequence to search for
    seq = str(section) + ',' + 'T'

    # Store last epochtime if in real time mode
    keyref = HOSTNAME_VAR + '/' + HOSTNAME + '.' + section + '_lastepoch.txt'

    if realtime:
        if not os.path.exists(keyref):
            if debug:
                logging.debug("DEBUG, no keyref file for this " + str(section) +
                       " section (searched for " + str(keyref) + "), no data or first execution")
        else:
            with open(keyref, "r") as f:
                for line in f:
                    myregex = 'last_epoch:\s(\d+)'
                    myregex_match = re.search(myregex, line)

                    # Standard header extraction
                    if myregex_match:
                        last_epoch_persection = myregex_match.group(1)

                        if debug:
                            logging.debug("DEBUG, Last known timestamp for " + str(section) +
                                  " section is " + str(last_epoch_persection))

        # In realtime mode, in case no per section information is available, let's use global epoch time
        try:
            last_epoch_persection
        except NameError:
            if debug:
                logging.debug("DEBUG: no last epoch information were found for " + str(section) +
                       " , using global last epoch time (gaps in data may occur if not the first time we run)")
            last_epoch_filter = last_known_epochtime
        else:
            if debug:
                logging.debug("DEBUG: Using per section last epoch time for event filtering "
                              "(no gaps in data should occur)")
            last_epoch_filter = last_epoch_persection

    # counter
    count = 0

    # sanity_check
    sanity_check = 1
    
    # Initialize num_cols_header to 0 (see sanity_check)
    num_cols_header = 0

    for line in data:

        # Extract sections
        if str(seq) in line:  # Don't use regex here for more performance

            # increment
            count += 1

    if count >= 1:

        # Open StringIO for temp in memory
        membuffer = cStringIO.StringIO()

        # Here we need a second temp space
        membuffer2 = cStringIO.StringIO()

        # counter
        count = 0

        for line in data:

            # Extract sections, and write to output
            myregex = r'^' + section + '[0-9]*' + '|ZZZZ.+'
            find_section = re.match(myregex, line)

            if find_section:

                line = subpctreplace(line)
                line = subreplace(line)

                # csv header

                # Extract header excluding data that always has Txxxx for timestamp reference
                myregex = '(' + section + ')\,([^T].+)'
                fullheader_match = re.search(myregex, line)

                if fullheader_match:
                    fullheader = fullheader_match.group(2)

                    # Replace "." by "_" only for header
                    fullheader = re.sub("\.", '_', fullheader)

                    # Replace any blank space before comma only for header
                    fullheader = re.sub(", ", ',', fullheader)

                    # Remove any blank space still present in header
                    fullheader = re.sub(" ", '', fullheader)

                    header_match = re.match(r'([a-zA-Z\-/_0-9]+,)([a-zA-Z\-/_0-9,]*)', fullheader)

                    if header_match:
                        header = header_match.group(2)

                        final_header = 'ZZZZ' + ',' + header + '\n'

                        # increment
                        count += 1

                        # Number of separators in final header
                        num_cols_header = final_header.count(',')

                        # Write header
                        membuffer.write(final_header),

                # Extract timestamp

                # Nmon V9 and prior do not have date in ZZZZ
                # If unavailable, we'll use the global date (AAA,date)
                ZZZZ_DATE = '-1'
                ZZZZ_TIME = '-1'

                # For Nmon V10 and more

                timestamp_match = re.match(r'^ZZZZ,(.+),(.+),(.+)\n', line)
                if timestamp_match:
                    ZZZZ_TIME = timestamp_match.group(2)
                    ZZZZ_DATE = timestamp_match.group(3)

                    # Replace month names with numbers
                    ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                    ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                    if is_windows:
                        ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                    else:
                        ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').strftime('%s')

                # For Nmon V9 and less

                if ZZZZ_DATE == '-1':
                    ZZZZ_DATE = DATE
                    timestamp_match = re.match(r'^ZZZZ,(.+),(.+)\n', line)

                    if timestamp_match:
                        ZZZZ_TIME = timestamp_match.group(2)

                        # Replace month names with numbers
                        ZZZZ_DATE = monthtonumber(ZZZZ_DATE)

                        ZZZZ_timestamp = ZZZZ_DATE + ' ' + ZZZZ_TIME

                        if is_windows:
                            ZZZZ_epochtime = time.mktime(time.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S'))
                        else:
                            ZZZZ_epochtime = datetime.datetime.strptime(ZZZZ_timestamp, '%d-%m-%Y %H:%M:%S').\
                                strftime('%s')

                # Extract Data
                myregex = r'^' + section + '\,(T\d+)\,(.+)\n'
                perfdata_match = re.match(myregex, line)
                if perfdata_match:
                    perfdata = perfdata_match.group(2)

                    # final perfdata
                    final_perfdata = ZZZZ_timestamp + ',' + perfdata + '\n'

                    if realtime:

                        if ZZZZ_epochtime > last_epoch_filter:

                            # increment
                            count += 1

                            # Analyse the first line of data: Compare number of fields in data with number of fields
                            # in header
                            # If the number of fields is higher than header, we assume this section is not consistent
                            # and will be entirely dropped
                            # This happens in rare times (mainly with old buggy nmon version) that the header is
                            # bad formatted (for example missing comma between fields identification)
                            # For performance purposes, we will test this only with first line of data and assume
                            # the data sanity based on this result
                            if count == 2:

                                # Number of separators in final header
                                num_cols_perfdata = final_perfdata.count(',')

                                if num_cols_perfdata > num_cols_header:

                                    msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                          ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                          ' fields in data, ' + str(num_cols_header) +\
                                          ' fields in header, extra fields detected (more fields in data than header)' \
                                          ', dropping this section to prevent data inconsistency'
                                    logging.debug(msg)
                                    ref.write(msg + "\n")

                                    if debug:
                                        logging.debug("\nDebug information: header content:")
                                        logging.debug(final_header)
                                        logging.debug("Debug information: data sample:")
                                        logging.debug(final_perfdata)

                                    # Affect a sanity check to 1, bad data
                                    sanity_check = 1

                                else:

                                    # Affect a sanity check to 0, good data
                                    sanity_check = 0

                            # Write perf data
                            membuffer.write(ZZZZ_timestamp + ',' + perfdata + '\n'),

                        else:
                            if debug:
                                logging.debug("DEBUG, " + str(section) + " ignoring event " + str(ZZZZ_timestamp) +
                                " ( " + str(ZZZZ_epochtime) + " is lower than last known epoch time for this section " +
                                       str(last_epoch_filter) + " )")

                    elif colddata:

                        # increment
                        count += 1

                        # Analyse the first line of data: Compare number of fields in data with number of fields
                        # in header
                        # If the number of fields is higher than header, we assume this section is not consistent
                        # and will be entirely dropped
                        # This happens in rare times (mainly with old buggy nmon version) that the header is bad
                        # formatted (for example missing comma between fields identification)
                        # For performance purposes, we will test this only with first line of data and assume the
                        # data sanity based on this result
                        if count == 2:

                            # Number of separators in final header
                            num_cols_perfdata = final_perfdata.count(',')

                            if num_cols_perfdata > num_cols_header:

                                msg = 'ERROR: hostname: ' + str(HOSTNAME) + ' :' + str(section) +\
                                      ' section data is not consistent: ' + str(num_cols_perfdata) +\
                                      ' fields in data, ' + str(num_cols_header) +\
                                      ' fields in header, extra fields detected (more fields in data than header),' \
                                      ' dropping this section to prevent data inconsistency'
                                logging.debug(msg)
                                ref.write(msg + "\n")

                                if debug:
                                    logging.debug("\nDebug information: header content:")
                                    logging.debug(final_header)
                                    logging.debug("Debug information: data sample:")
                                    logging.debug(final_perfdata)

                                # Affect a sanity check to 1, bad data
                                sanity_check = 1

                            else:

                                # Affect a sanity check to 0, good data
                                sanity_check = 0

                        # Write perf data
                        membuffer.write(ZZZZ_timestamp + ',' + perfdata + '\n'),

        if sanity_check == 0:

            # Reset counter
            count = 0

            # Open final for writing
            with open(currsection_output, "ab") as currsection:

                # Rewind temp
                membuffer.seek(0)

                writer = csv.writer(membuffer2)
                writer.writerow(
                    ['timestamp', 'OStype', 'type', 'serialnum', 'hostname', 'logical_cpus',
                     'interval', 'snapshots', 'ZZZZ', 'device', 'value'])

                # increment
                count += 1

                for d in csv.DictReader(membuffer):
                    ZZZZ = d.pop('ZZZZ')
                    for device, value in sorted(d.items()):
                        # increment
                        count += 1

                        row = [ZZZZ_epochtime, OStype, section, SN, HOSTNAME,
                               logical_cpus, INTERVAL, SNAPSHOTS, ZZZZ, device, value]
                        writer.writerow(row)

                        # End for

                # Rewind secondary temp
                membuffer2.seek(0)

                # Write final kv file in append mode
                write_kv(membuffer2, currsection_output)

            # Show number of lines extracted
            result = str(section) + " section: Wrote" + " " + str(count) + " lines"
            logging.info(result)
            ref.write(result + "\n")

            # In realtime, Store last epoch time for this section
            if realtime:
                with open(keyref, "wb") as f:
                    f.write("last_epoch: " + ZZZZ_epochtime + "\n")

            # Discard memory membuffer
            membuffer.close()
            membuffer2.close()

        elif sanity_check == 0:

            # Discard memory membuffer
            membuffer.close()

            # End for

# Run
if OStype in ("Solaris", "Unknown"):
    for section in solaris_WLM:
        solaris_wlm_section_fn(section)

    for section in solaris_VxVM:
        dynamic_section_fn(section)

    for section in solaris_dynamic_various:
        dynamic_section_fn(section)

###################
# End
###################

# Time required to process
end_time = time.time()
result = "Elapsed time was: %g seconds" % (end_time - start_time)
logging.info(result)
ref.write(result + "\n")

# exit
sys.exit(0)
