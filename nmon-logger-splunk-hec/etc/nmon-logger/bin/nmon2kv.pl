#!/usr/bin/perl

# Program name: nmon2kv.pl
# Compatibility: Any
# Purpose - convert nmon files into kv flow, this script is a back ported version of the origin csv2mon.pl
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
# - 07/17/2016, V1.0.1: Guilhem Marchand:
#                                          - Mirror update of the TA-nmon
# - 2017/06/01, V1.0.2: Guilhem Marchand:
#                                          - Mirror update from TA-nmon
#                                          - Fix per section last epoch not working properly
# - 2017/09/04, V1.0.4: Guilhem Marchand:
#                                          - Mirror update from TA-nmon
# - 2017/06/05, V1.0.5: Guilhem Marchand:
#                                          - Mirror update of the TA-nmon
# - 2017/15/07: V1.0.6: Guilhem Marchand:
#                                           - Optimize nmon_processing output and reduce volume of data to be generated #37
# - 2017/27/07: V1.0.7: Guilhem Marchand:
#                                           - Splunk HEC implementation

$version = "1.0.7";

use Time::Local;
use Time::HiRes;
use Getopt::Long;
use POSIX 'strftime';
use File::Copy;

#################################################
##      Args
#################################################

# Default values

my $OPMODE   = "";
my $NMON_VAR = "/var/log/nmon-logger";
my $NMON_APP = "/etc/nmon-logger";

$result = GetOptions(
    "mode=s"              => \$OPMODE,               # string
    "nmon_var=s"          => \$NMON_VAR,             # string
    "nmon_app=s"          => \$NMON_APP,             # string
    "version"             => \$VERSION,              # flag
    "use_fqdn"            => \$USE_FQDN,             # flag
    "splunk_http_url=s"   => \$SPLUNK_HTTP_URL,      # string
    "splunk_http_token=s" => \$SPLUNK_HTTP_TOKEN,    # string
    "silent"    => \$SILENT,       # flag
    "no_local_log"    => \$NO_LOCAL_LOG,       # flag
    "help"                => \$help,                 # flag
    "debug"               => \$DEBUG,                # flag
);

# Show version
if ($VERSION) {
    print("nmon2kv.pl version $version \n");

    exit 0;
}

# Show help
if ($help) {

    print( "

Help for nmon2kv.pl:

Perl nmon2kv script will convert nmon performance and configuration data into key=value mode log data.
This script has been designed to read the nmon file from stdin. (eg. cat <my file> | ./nmon2kv.pl)

Available options are:

--mode <realtime | colddata | fifo> :Force the script to consider the data as cold data (nmon process has over) , real time data (nmon is running) or fifo.
--use_fqdn :Use the host fully qualified domain name (fqdn) as the hostname value instead of the value returned by nmon.
**CAUTION:** This option must not be used when managing nmon data generated out of Splunk (eg. central repositories)
--nmon_var <directory path> :Sets the output Home directory for Nmon (Default: /var/log/nmon)
--nmon_app <directory path> :sets the application Home directory for Nmon (Default: /etc/nmon)
--splunk_http_url :Defines the URL for Splunk http forwarding, example: --splunk_http_url  https://host.splunk.com:8088/services/collector/event
--splunk_http_token :Defines the value of the Splunk HEC token, example: --splunk_http_token B07538E6-729F-4D5B-8AE1-30E93646C65A
--silent: Do not output the per section detail logging to save data volume
--no_local_log: Do not write local log on machine file system
--debug :Activate debugging mode for testing purposes
--version :Show current program version \n
"
    );

    exit 0;
}

#################################################
##      Parameters
#################################################

# Customizations goes here:
# Sections of Performance Monitors with standard dynamic header but no "device" notion that would require the data to be transposed
# You can add or remove any section depending on your needs
@static_vars = "";

# Some specific sections per OS
@Solaris_static_section = "";

# Some specfic sections for micro partitions (AIX or Power Linux)
@LPAR_static_section = "";

# This is the TOP section which contains Performance data of top processes
# It has a specific structure and requires specific treatment
@top_vars = "";

# This is the UARG section which contains full command line arguments with some other information such as PID, user, group and so on
# It has a specific structure and requires specific treatment
@uarg_vars = "";

# Sections of Performance Monitors with Dynamic header (eg. device context) and that can be incremented (DISKBUSY1...)
@dynamic_vars1 = "";

# Sections that won't be incremented
@dynamic_vars2 = "";

# disks extended statistics (DG*)
@disk_extended_section = "";

# Sections of Performance Monitors for Solaris

# Zone, Project, Task... performance
@solaris_WLM = "";

# Veritas Storage Manager
@solaris_VxVM = "";

@solaris_dynamic_various = "";

# AIX only dynamic sections
@AIX_dynamic_various = "";

# AIX Workload Management
@AIX_WLM = "";

# nmon external
@nmon_external = "";

# nmon external with transposition of data
@nmon_external_transposed = "";

#################################################
## 	Your Customizations Go Here
#################################################

# Processing starting time
my $t_start = [Time::HiRes::gettimeofday];

# Initial states for Analysis
my $realtime = "False";
my $colddata = "False";
my $fifo     = "False";

# Splunk HEC
my $use_splunk_http          = "False";
my $splunk_http_token_is_set = "False";

if ( $splunk_http_token eq "insert_your_splunk_http_token" ) {
    $use_splunk_http          = "False";
    $splunk_http_token_is_set = "False";
}

else {
    $use_splunk_http          = "True";
    $splunk_http_token_is_set = "True";
}

# Local time
my $time = strftime "%d-%m-%Y %H:%M:%S", localtime;

# Local Time in epoch
my $time_epoch = time();

# timestamp used to name csv files
$csv_timestamp = strftime "%Y%m%d%H%M%S", localtime;

# Verify NMON_VAR definition
if ( !-d "$NMON_VAR" ) {
    print("$time ERROR: The log directory NMON_VAR does not exist.\n");
    print(
"Please create the directory manually or specify the --nmon_var <path directory> option. (we tried $NMON_VAR) \n"
    );
    die;
}

# APP
my $APP = $NMON_APP;

# load configuration from json config file
# the config_file json may exist in default or local (if customized)
# this will define the list of nmon section we want to extract

if ( -e "$APP/local/nmonparser_config.json" ) {
    $json_config = "$APP/local/nmonparser_config.json";
}
else {
    $json_config = "$APP/default/nmonparser_config.json";
}

open( $json, "< $json_config" )
  or die "ERROR: Can't open $json_config : $!";

while (<$json>) {
    chomp($_);

    $_ =~ s/\"//g;       #remove quotes
    $_ =~ s/\,\s/,/g;    #remove comma space

    # static_section
    if ( $_ =~ /^\s*static_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @static_vars = split( ',', $1 );
    }

    # Solaris_static_section
    if ( $_ =~ /^\s*Solaris_static_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @Solaris_static_section = split( ',', $1 );
    }

    # LPAR_static_section
    if ( $_ =~ /^\s*LPAR_static_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @LPAR_static_section = split( ',', $1 );
    }

    # top_section
    if ( $_ =~ /^\s*top_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @top_vars = split( ',', $1 );
    }

    # uarg_section
    if ( $_ =~ /^\s*uarg_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @uarg_vars = split( ',', $1 );
    }

    # dynamic_section1
    if ( $_ =~ /^\s*dynamic_section1:\[([\w\,\s]*)\],{0,}$/ ) {
        @dynamic_vars1 = split( ',', $1 );
    }

    # dynamic_section2
    if ( $_ =~ /^\s*dynamic_section2:\[([\w\,\s]*)\],{0,}$/ ) {
        @dynamic_vars2 = split( ',', $1 );
    }

    # disk_extended_section
    if ( $_ =~ /^\s*disk_extended_section:\[([\w\,\s]*)\],{0,}$/ ) {
        @disk_extended_section = split( ',', $1 );
    }

    # solaris_WLM
    if ( $_ =~ /^\s*solaris_WLM:\[([\w\,\s]*)\],{0,}$/ ) {
        @solaris_WLM = split( ',', $1 );
    }

    # solaris_VxVM
    if ( $_ =~ /^\s*solaris_VxVM:\[([\w\,\s]*)\],{0,}$/ ) {
        @solaris_VxVM = split( ',', $1 );
    }

    # solaris_dynamic_various
    if ( $_ =~ /^\s*solaris_dynamic_various:\[([\w\,\s]*)\],{0,}$/ ) {
        @solaris_dynamic_various = split( ',', $1 );
    }

    # AIX_dynamic_various
    if ( $_ =~ /^\s*AIX_dynamic_various:\[([\w\,\s]*)\],{0,}$/ ) {
        @AIX_dynamic_various = split( ',', $1 );
    }

    # AIX_WLM
    if ( $_ =~ /^\s*AIX_WLM:\[([\w\,\s]*)\],{0,}$/ ) {
        @AIX_WLM = split( ',', $1 );
    }

    # nmon_external
    if ( $_ =~ /^\s*nmon_external:\[([\w\,\s]*)\],{0,}$/ ) {
        @nmon_external = split( ',', $1 );
    }

    # nmon_external
    if ( $_ =~ /^\s*nmon_external_transposed:\[([\w\,\s]*)\],{0,}$/ ) {
        @nmon_external_transposed = split( ',', $1 );
    }

}

close $json;

# Identify the Technical Add-on version
my $APP_CONF_FILE = "$APP/default/app.conf";
my $addon_version = "Unknown";

if ( -e $APP_CONF_FILE ) {

    # Open
    open FILE, '+<', "$APP_CONF_FILE" or die "$time ERROR:$!\n";

    while ( defined( my $l = <FILE> ) ) {
        chomp $l;

        # If SN is undetermined, set it equal to HOSTNAME
        if ( $l =~ m/version\s*=\s*([\d|\.]*)/ ) {
            $addon_version = $1;
        }
    }
}

# var main directory
my $APP_VAR = "$NMON_VAR/var";

# If may main directories do not exist
if ( !-d "$APP_VAR" ) { mkdir "$APP_VAR"; }

# Spool directory for NMON files processing
my $SPOOL_DIR = "$APP_VAR/spool";
if ( !-d "$SPOOL_DIR" ) { mkdir "$SPOOL_DIR"; }

#  Output directory of csv files to be managed by Splunk
my $OUTPUT_DIR = "$APP_VAR/csv_workingdir";
if ( !-d "$OUTPUT_DIR" ) { mkdir "$OUTPUT_DIR"; }

# Directory for Performance log
my $OUTPUTFINAL_DIR = "$NMON_VAR";

# Directory for Configuration log
my $OUTPUTCONF_DIR = "$NMON_VAR";

# ID reference file, will be used to temporarily store the last execution result for a given nmon file, and prevent Splunk from
# generating duplicates by relaunching the conversion process
# Splunk when using a custom archive mode, launches twice the custom script

# Supplementary note: Since V1.2.2, ID_REF & CONFIG_REF are overwritten if running real time mode
$ID_REF = "$APP_VAR/id_reference.txt";

# Config Reference file
$CONFIG_REF = "$APP_VAR/config_reference.txt";

# BBB extraction flag
$BBB_FLAG = "$APP_VAR/BBB_status.flag";

# Splunk HEC only: store the final batch file to be streamed (remove any pre-existing file)
$SPLUNK_HEC_BATCHFILE = "$APP_VAR/splunk_hec_perfdata_batch.dat";
if ( -e $SPLUNK_HEC_BATCHFILE ) {
            unlink $SPLUNK_HEC_BATCHFILE;
}

#################################################
## 	Various
#################################################

# Used for date string to epoch time
my %month;
@month{qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/} = 0 .. 11;

%mon2num = qw(
  jan 1  feb 2  mar 3  apr 4  may 5  jun 6
  jul 7  aug 8  sep 9  oct 10 nov 11 dec 12
);

####################################################################
#############		Main Program
####################################################################

# Verify existence of OUTPUT_DIR
if ( !-d "$SPOOL_DIR" ) {
    print("\n$time ERROR: Spool Directory $SPOOL_DIR does not exist !\n");
    die;
}

# Verify existence of OUTPUT_DIR
if ( !-d "$OUTPUT_DIR" ) {
    print(
"\n $time ERROR: Directory for csv output $OUTPUT_DIR does not exist !\n"
    );
    die;
}

# Initialize common variables
&initialize;

# Clean spool directory at program start-up
unlink glob "$SPOOL_DIR/*.nmon";

# Clean csv directory at program start-up
unlink glob "$OUTPUT_DIR/*.csv";

# Read nmon file from stdin (eg. cat <my nmon file> | nmon2kv)
# will remove blank lines if any
my $file = "$SPOOL_DIR/nmon2kv.$$.nmon";
open my $fh, '>', $file or die $!;

while (<STDIN>) {
    next if /^$/;
    last if /^$/;
    print $fh $_;
}
close $fh;

# Open temp nmon
open FILE, '+<', "$file" or die "$time ERROR:$!\n";

####################################################################################################
#############		NMON data structure verification				############
####################################################################################################

# Set some default values
my $SN       = "-1";
my $HOSTNAME = "-1";
my $DATE     = "-1";

my $nmon_day    = "-1";
my $nmon_month  = "-1";
my $nmon_year   = "-1";
my $nmon_hour   = "-1";
my $nmon_minute = "-1";
my $nmon_second = "-1";

my $TIME         = "-1";
my $logical_cpus = "-1";
my $virtual_cpus = "-1";

my $INTERVAL = "-1";
my $SNAPSHOT = "-1";

my $OStype = "Unknown";

# Set HOSTNAME
if ($USE_FQDN) {
    chomp( $HOSTNAME = `hostname -f` );
}

while ( defined( my $l = <FILE> ) ) {
    chomp $l;

# Set HOSTNAME
# if the option --use_fqdn has been set, use the fully qualified domain name by the running OS
# The value will be equivalent to the stdout of the os "hostname -f" command
# CAUTION: This option must not be used to manage nmon data out of Splunk ! (eg. central repositories)

    if (not $USE_FQDN) {
        if ( ( rindex $l, "AAA,host," ) > -1 ) {
            ( my $t1, my $t2, $HOSTNAME ) = split( ",", $l );
        }
    }

    # Set VERSION
    if ( ( rindex $l, "AAA,version," ) > -1 ) {
        ( my $t1, my $t2, $VERSION ) = split( ",", $l );
    }

    # Set DATE
    if ( ( rindex $l, "AAA,date," ) > -1 ) {
        ( my $t1, my $t2, $DATE ) = split( ",", $l );
    }

    # Set TIME
    if ( ( rindex $l, "AAA,time," ) > -1 ) {
        ( my $t1, my $t2, $TIME ) = split( ",", $l );
    }

    # Set day, month, year
    if ( $l =~ m/AAA,date,(\w+)\-(\w+)\-(\w+)/ ) {
        $nmon_day   = $1;
        $nmon_month = $2;
        $nmon_year  = $3;
    }

    # Set hour, minute, second
    if ( $l =~ m/AAA,time,(\d+)\:(\d+)[\:|\.](\d+)/ ) {
        $nmon_hour   = $1;
        $nmon_minute = $2;
        $nmon_second = $3;
    }

    # Get Nmon version
    if ( $l =~ m/AAA\,version\,(.+)/ ) {
        $VERSION = $1;
    }

    # Get interval
    if ( $l =~ m/AAA\,interval\,(d+)/ ) {
        $INTERVAL = $1;
    }

    # Get interval
    if ( $l =~ m/AAA\,snapshots\,(d+)/ ) {
        $SNAPSHOTS = $1;
    }

    # Get logical_cpus
    if ( $l =~ m/AAA\,cpus\,\d+\,(\d+)/ ) {
        $logical_cpus = $1;
    }

    # If not defined in second position, set it from first
    elsif ( $l =~ m/AAA\,cpus\,(\d+)/ ) {
        $logical_cpus = $1;
    }

    # Get virtual_cpus
    if ( $l =~ m/BBB[a-zA-Z].+Online\sVirtual\sCPUs.+\:\s(\d+)\"/ ) {
        $virtual_cpus = $1;
    }

    # If undefined, set it equal to logical_cpus
    if ( $virtual_cpus == "-1" ) {
        $virtual_cpus = $logical_cpus;
    }

# Search for old nmon versions time format, eg. dd/mm/yy
# If found, let's convert it into the nmon format used with later versions: dd/MMM/YYYY

    if ( $l =~ m/AAA,date,[0-9]+\/[0-9]+\/[0-9]+/ ) {
        $obsolete_nmon = "-1";
    }

# Verify we do not have any line that contain ZZZZ without beginning the line by ZZZZ
# In such case, the nmon data is bad and buggy, converting it would generate

    if ( $l =~ m/.+ZZZZ,/ ) {
        $truncated_nmon = "-1";
    }

    # Identify Linux hosts
    if ( $l =~ m/AAA,OS,Linux/ ) {
        $OStype = "Linux";
    }

    # Identify Solaris hosts
    if ( $l =~ m/AAA,OS,Solaris,.+/ ) {
        $OStype = "Solaris";
    }

    # Identify AIX hosts
    if ( $l =~ m/^AAA,AIX,(.+)/ ) {
        $OStype = "AIX";
    }

}

# Process nmon file provided in argument
@nmon_files = "$SPOOL_DIR/nmon2kv.$$.nmon";

@nmon_files = sort(@nmon_files);
chomp(@nmon_files);

foreach $FILENAME (@nmon_files) {

    $start = time();
    @now   = localtime($start);
    $now   = join( ":", @now[ 2, 1, 0 ] );

    # Parse nmon file, skip if unsuccessful
    if ( (&get_nmon_data) gt 0 ) { next; }
    $now = time();
    $now = $now - $start;

    # Get nmon file number of lines
    open( FILE, $FILENAME ) or die "$time ERROR: Can't open '$FILENAME': $!";
    $lines++ while (<FILE>);
    close FILE;

    # If SN could not be identified
    if ( $SN == "-1" ) {
        $SN = $HOSTNAME;
    }

    # Get nmon file size in bytes
    my $bytes = -s $FILENAME;

    # Get idnmon
    my $idnmon = "${DATE}:${TIME},${HOSTNAME},${SN},$bytes";

    # Print Main information
    print "nmon2csv: ${time} Reading NMON data: $lines lines $bytes bytes\n";

    # Print NMON_VAR
    print "Nmon var directory (\$NMON_VAR): $NMON_VAR \n";

    # Show program version
    print "nmon2kv version: $version \n";

    # Show addon type
    print "addon type: $APP \n";

    # Show application version
    print "addon version: $addon_version \n";

    # Show OS guest
    print "Guest Operating System: $^O\n";

    # Show NMON OS
    print "NMON OStype: $OStype \n";

    # Show perl version
    print "Perl version: $] \n";

    # Print an informational message if running in silent mode
    if ($SILENT) {
        print "Output mode is configured to run in minimal mode using the --silent option\n";
    }

    # Show Nmon version
    print "NMON VERSION: $VERSION \n";

    # Show hostname
    print "HOSTNAME: $HOSTNAME \n";

    # Show TIME
    print "TIME of Nmon Data: $TIME \n";

    # Show DATE
    print "DATE of Nmon Data: $DATE \n";

    # Show INTERVAL
    print "INTERVAL: $INTERVAL \n";

    # Show SNAPSHOTS
    print "SNAPSHOTS: $SNAPSHOTS \n";

    # Show logical_cpus
    print "logical_cpus: $logical_cpus \n";

    # Show virtual_cpus
    print "virtual_cpus: $virtual_cpus \n";

    # Show SerialNumber
    print "SerialNumber: $SN \n";

    #
    # PERMANENT FAILURES: Avoid inconsistent data to be generated
    #

    if ( $HOSTNAME == "-1" ) {
        print("ERROR: The hostname could not be extracted from Nmon data ! \n");
        unlink $FILENAME;
        exit 1;
    }

    if ( $DATE == "-1" ) {
        print("ERROR: date could not be extracted from Nmon data ! \n");
        unlink $FILENAME;
        exit 1;
    }

    if ( $TIME == "-1" ) {
        print("ERROR: time could not be extracted from Nmon data ! \n");
        unlink $FILENAME;
        exit 1;
    }

    if ( $logical_cpus == "-1" ) {
        print(
"ERROR: The number of logical cpus (logical_cpus) could not be extracted from Nmon data ! \n"
        );
        unlink $FILENAME;
        exit 1;
    }

    if ( $truncated_nmon == "-1" ) {
        print(
"ERROR: hostname: $HOSTNAME Detected Bad Nmon structure, found ZZZZ lines truncated! (ZZZZ lines contains the event timestamp and should always begin the line) \n"
        );
        print("ERROR: hostname: $HOSTNAME Ignoring nmon data \n");
        unlink $FILENAME;
        exit 1;
    }

    if ( $truncated_nmon == "-1" ) {
        print(
"ERROR: hostname: $HOSTNAME Detected obsolete Nmon version, please consider upgrading this hosts! \n"
        );
        print("ERROR: hostname: $HOSTNAME Ignoring nmon data \n");
        unlink $FILENAME;
        exit 1;
    }

    # If virtual_cpus could not be identified, set it equal to logical_cpus
    if ( $virtual_cpus == "-1" ) {
        $virtual_cpus = $logical_cpus;
    }

#####################
    # Data status store #
#####################

# Various status are stored in different files
# This includes the id check file, the config check file and status per section containing last epochtime proceeded
# These items will be stored in a per host dedicated directory

    # create a directory under APP_VAR
    # This directory will be used to store per section last epochtime status
    my $HOSTNAME_VAR = "$APP_VAR/${HOSTNAME}_${SN}";
    if ( !-d "$HOSTNAME_VAR" ) { mkdir "$HOSTNAME_VAR"; }

    # Overwrite ID_REF and CONFIG_REF
    $ID_REF     = "$HOSTNAME_VAR/${HOSTNAME}.id_reference.txt";
    $CONFIG_REF = "$HOSTNAME_VAR/${HOSTNAME}.config_reference.txt";
    $BBB_FLAG   = "$HOSTNAME_VAR/${HOSTNAME}.BBB_status.flag";

###############
    # ID Check #
###############

# This section prevents Splunk from generating duplicated data for the same Nmon file
# While using the archive mode, Splunk may opens twice the same file sequentially
# If the Nmon file id is already present in our reference file, then we have already proceeded this Nmon and nothing has to be done
# Last execution result will be extracted from it to stdout

    # Change . to : if present in TIME
    $TIME =~ s/\./\:/g;

    # Date of starting Nmon (format: DD-MM-YYYY hh:mm:ss)
    my $NMON_DATE = "$DATE $TIME";

    $NMON_DATE =~ s/JAN/01/g;
    $NMON_DATE =~ s/FEB/02/g;
    $NMON_DATE =~ s/MAR/03/g;
    $NMON_DATE =~ s/APR/04/g;
    $NMON_DATE =~ s/MAY/05/g;
    $NMON_DATE =~ s/JUN/06/g;
    $NMON_DATE =~ s/JUL/07/g;
    $NMON_DATE =~ s/AUG/08/g;
    $NMON_DATE =~ s/SEP/09/g;
    $NMON_DATE =~ s/OCT/10/g;
    $NMON_DATE =~ s/NOV/11/g;
    $NMON_DATE =~ s/DEC/12/g;

# Convert date string to epoch time (note: we could have made this easier but we want to only use core modules !)
    my ( $day, $month, $year, $hour, $min, $sec ) = split /\W+/, $NMON_DATE;

    # Set it global
    $STARTING_EPOCHTIME =
      timelocal( $sec, $min, $hour, $day, $month - 1, $year );

    # Search for the last timestamp in data

    # Open NMON file for reading
    if ( !open( FIC, $file ) ) {
        die( "Error while trying to open NMON Source file '" . $file . "'" );
    }

    # Initialize variables
    my $timestamp = "";

    while ( defined( my $l = <FIC> ) ) {
        chomp $l;

        # Get timestamp"
        if ( ( rindex $l, "ZZZZ," ) > -1 ) {
            ( my $t1, my $t2, my $timestamptmp1, my $timestamptmp2 ) =
              split( ",", $l );
            $timestamp = $timestamptmp2 . " " . $timestamptmp1;

            $timestamp =~ s/JAN/01/g;
            $timestamp =~ s/FEB/02/g;
            $timestamp =~ s/MAR/03/g;
            $timestamp =~ s/APR/04/g;
            $timestamp =~ s/MAY/05/g;
            $timestamp =~ s/JUN/06/g;
            $timestamp =~ s/JUL/07/g;
            $timestamp =~ s/AUG/08/g;
            $timestamp =~ s/SEP/09/g;
            $timestamp =~ s/OCT/10/g;
            $timestamp =~ s/NOV/11/g;
            $timestamp =~ s/DEC/12/g;

     # Convert timestamp string to epoch time (from format: DD-MM-YYYY hh:mm:ss)
            my ( $day, $month, $year, $hour, $min, $sec ) = split /\W+/,
              $timestamp;
            $ZZZZ_epochtime =
              timelocal( $sec, $min, $hour, $day, $month - 1, $year );

        }

    }

    # Last epochtime in data is
    $ending_epochtime = $ZZZZ_epochtime;

    # Evaluate if we are dealing with real time data or cold data

    if ( $OPMODE eq "colddata" ) {

        $colddata = True;
        print "ANALYSIS: Enforcing colddata mode using --mode option \n";

    }

    elsif ( $OPMODE eq "realtime" ) {

        $realtime = True;
        print("ANALYSIS: Enforcing realtime mode using --mode option \n");

        # Override ID_REF & CONFIG_REF
        $ID_REF     = "$HOSTNAME_VAR/${HOSTNAME}.id_reference.txt";
        $CONFIG_REF = "$HOSTNAME_VAR/${HOSTNAME}.config_reference.txt";
        $BBB_FLAG   = "$HOSTNAME_VAR/${HOSTNAME}.BBB_status.flag";

    }

    elsif ( $OPMODE eq "fifo" ) {

        $fifo = True;
        print("ANALYSIS: Enforcing fifo mode using --mode option \n");

    }

    elsif ( ( ($time_epoch) - ( 4 * $INTERVAL ) ) > $ending_epochtime ) {

        $colddata = True;
        print "ANALYSIS: Assuming Nmon cold data \n";

    }

    else {

        $realtime = True;
        print "ANALYSIS: Assuming Nmon realtime data \n";

        # Override ID_REF & CONFIG_REF
        $ID_REF     = "$HOSTNAME_VAR/${HOSTNAME}.id_reference.txt";
        $CONFIG_REF = "$HOSTNAME_VAR/${HOSTNAME}.config_reference.txt";
        $BBB_FLAG   = "$HOSTNAME_VAR/${HOSTNAME}.BBB_status.flag";

    }

    # Set the full idnmon
    $idnmon = "$idnmon,$STARTING_EPOCHTIME,$ending_epochtime";

    # Set the partial idnmon
    $partial_idnmon = "$idnmon,$STARTING_EPOCHTIME";

    # Open ID_REF file

    # Notes: fifo mode will always proceed data

    if ( -e $ID_REF ) {

        open( ID_REF, "< $ID_REF" ) or die "ERROR: Can't open $ID_REF : $!";
        chomp $ID_REF;

        if ( $realtime eq "True" ) {

            if ( grep { /$idnmon/ } <ID_REF> ) {

                # If the idnmon was found, print file content and exit
                open( ID_REF, "< $ID_REF" )
                  or die "ERROR: Can't open $ID_REF : $!";
                while (<ID_REF>) {
                    print;
                }
                close ID_REF;

                # remove spool nmon
                unlink $file;

                exit;

            }
            else {

# If in realtime mode, extract the last known epochtime processed, only events after this timestamp will be extracted
                open( ID_REF, "< $ID_REF" )
                  or die "ERROR: Can't open $ID_REF : $!";
                while ( defined( my $l = <ID_REF> ) ) {
                    chomp $l;

                    # Get timestamp"
                    if ( ( rindex $l, "Ending_epochtime" ) > -1 ) {
                        ( my $t1, my $timestamp ) =
                          split( ": ", $l );
                        $last_known_epochtime = $timestamp;
                        print(
                            "Last known timestamp is: $last_known_epochtime \n"
                        );
                    }

                }

            }
        }

        elsif ( $colddata eq "True" ) {

            if ( grep { /$partial_idnmon/ } <ID_REF> ) {

                # If the idnmon was found, print file content and exit
                open( ID_REF, "< $ID_REF" )
                  or die "ERROR: Can't open $ID_REF : $!";
                while (<ID_REF>) {
                    print;
                }
                close ID_REF;

                # remove spool nmon
                unlink $file;

                exit;

            }
        }

    }

# If last_known_epochtime could not be found (eg. we never proceeded this nmon file), set it equal to starting_epochtime
    if ( $last_known_epochtime eq "" ) {

        $last_known_epochtime = $STARTING_EPOCHTIME;

    }

    # If we are here, then we need to process

    # Open for writing, and write the idnmon to it
    open( ID_REF, "> $ID_REF" ) or die "ERROR: Can't open $ID_REF : $!";
    if ( $realtime eq "True" ) {
        print ID_REF "NMON ID: $idnmon\n";

        # Print idnmon for stdout
        print "NMON ID: $idnmon\n";
    }
    elsif ( $colddata eq "True" ) {
        print ID_REF "NMON ID: $partial_idnmon\n";

        # Print idnmon for stdout
        print "NMON ID: $partial_idnmon\n";
    }

    # Open ID_REF for writing in append mode
    open( ID_REF, ">>$ID_REF" );

    # Show and Save timestamps information
    print "Starting_epochtime: $STARTING_EPOCHTIME \n";
    print ID_REF "Starting_epochtime: $STARTING_EPOCHTIME \n";
    print "Ending_epochtime: $ending_epochtime \n";
    print ID_REF "Ending_epochtime: $ending_epochtime \n";
    print ID_REF "Last known timestamp is: $last_known_epochtime \n";

####################################################################################################
#############		NMON config Section						############
####################################################################################################

    # Extract config elements from NMON files, section AAA, section BBB

    # CONFIG Section
    @config_vars = ("CONFIG");

    foreach $key (@config_vars) {
        $BASEFILENAME = "$OUTPUTCONF_DIR/nmon_configdata.log";

        # Set default for config_run:
        # 0 --> Extract configuration
        # 1 --> Don't Extract configuration
        # default is extract
        my $config_run = 0;

# If the BBB_FLAG is found and we are in real time, the last configuration extraction did not extracted BBB section, proceed any way

        if ( -e $BBB_FLAG ) {

            if ( $realtime eq "True" ) {

                print
"CONFIG section: BBB flag found (BBB sections could not yet be extracted), enforcing configuration extraction \n";
                print ID_REF
"CONFIG section: BBB flag found (BBB sections could not yet be extracted), enforcing configuration extraction \n";

                # run sub routine
                &config_extract

            }

# remove the flag, if the BBB extraction fails again, it will be created again (in real mode)
            unlink $BBB_FLAG;

        }

        else {

            # Search in ID_REF for a last matching execution
            if ( -e $CONFIG_REF ) {

                open( CONFIG_REF, "< $CONFIG_REF" )
                  or die "ERROR: Can't open $CONFIG_REF : $!";
                chomp $CONFIG_REF;

                # Only proceed if hostname has the same value
                if ( <CONFIG_REF> =~ m/$HOSTNAME:\s(\d+)/ ) {

                    $config_lastepoch = $1;

                }

                # Evaluate the delta
                $time_delta = ( $time_epoch - $config_lastepoch );

                # Only generate data once per hour
                if ( $time_delta < 3600 ) {

                    $config_run = "1";

                }

                elsif ( $time_delta > 3600 ) {

                    $config_run = "0";

                }

            }

            if ( $config_run eq "0" ) {

# Real time restricts configuration extraction once per hour, with the exception of the BBB extraction failure
                if ( $realtime eq "True" || $fifo eq "True" ) {

                    $limit = ( ($STARTING_EPOCHTIME) + ( 4 * $INTERVAL ) );

                    print "last known epoch is $last_known_epochtime \n";

                    if ( $last_known_epochtime < $limit ) {

                        print "CONFIG section will be extracted \n";

                        # run sub routine
                        &config_extract

                    }

                    else {

                        print
"CONFIG section: Assuming we already extracted for this file \n";

                        print ID_REF
"CONFIG section: Assuming we already extracted for this file \n";

                    }

                }

                # cold data mode implies to always extract config
                elsif ( $colddata eq "True" ) {

                    # run sub routine
                    &config_extract

                }

            }

            elsif ( $config_run eq "1" ) {

                print
"CONFIG section: will not be extracted (time delta of $time_delta seconds is inferior to 1 hour) \n";
                print ID_REF
"CONFIG section: will not be extracted (time delta of $time_delta seconds is inferior to 1 hour) \n";

            }

        }

    }    # end foreach

###################################################""

####################################################################################################
#############		NMON Sections with static fields (eg. no devices)		############
####################################################################################################

    # Static variables (number of fields always the same)

    foreach $key (@static_vars) {
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
        $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

        &static_sections_insert($key);
        $now = time();
        $now = $now - $start;

    }    # end foreach

    foreach $key (@nmon_external) {
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
        $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

        &static_sections_insert($key);
        $now = time();
        $now = $now - $start;

    }    # end foreach

    # These sections are specific for Micro Partitions, can be AIX or PowerLinux
    if ( $OStype eq "AIX" || $OStype eq "Linux" || $OStype eq "Unknown" ) {

        foreach $key (@LPAR_static_section) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &static_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }    # end foreach

    }

    # Solaris Specific
    if ( $OStype eq "Solaris" || $OStype eq "Unknown" ) {

        foreach $key (@Solaris_static_section) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &static_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }    # end foreach

    }

####################################################################################################
#############		NMON TOP Section						############
####################################################################################################

    # TOP Section (specific)

    my $sanity_check = 0;

    foreach $key (@top_vars) {
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";

        # Open NMON file for reading
        if ( !open( FIC, $file ) ) {
            die(
                "Error while trying to open NMON Source file '" . $file . "'" );
        }

        # If we find the section, enter the process
        if ( grep { /TOP,\d+/ } <FIC> ) {

            @rawdataheader = grep( /^TOP,\+PID,/, @nmon );
            if ( @rawdataheader < 1 ) {
                $msg =
"WARN: hostname: $HOSTNAME :$key section data is not consistent: the data header could not be identified, dropping the section to prevent data inconsistency \n";
                print "$msg";
                print ID_REF "$msg";

                $sanity_check = "1";

            }

            else {

                unless ( open( INSERT, ">$BASEFILENAME" ) ) {
                    die("ERROR: Can not open /$BASEFILENAME\n");
                }

            }

            # Initialize variables
            my $section   = "";
            my $timestamp = "";
            $count = 0;

            # Store last epochtime if in real time mode
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            if ( $realtime eq "True" ) {

                if ( -e $keyref ) {

                    open( keyref, "< $keyref" )
                      or die "ERROR: Can't open $keyref : $!";
                    while ( defined( my $l = <keyref> ) ) {
                        chomp $l;

                        # Get epoch time
                        if ( ( rindex $l, "last_epoch" ) > -1 ) {
                            ( my $t1, my $t2 ) =
                              split( ": ", $l );
                            $last_epoch_persection = $t2;

                            if ($DEBUG) {
                                print
"DEBUG, Last known timestamp for $key section is: $last_epoch_persection \n";
                            }
                        }

                    }

                }

                else {

                    if ($DEBUG) {
                        print
"DEBUG, no keyref for file for this $key section (searched for $keyref), no data or first execution \n";
                    }

                }

                # Define if we use global last epoch or per section last epoch
                if ( not $last_epoch_persection ) {

                    if ($DEBUG) {
                        print
"DEBUG: no last epoch information were found for $key section, using global last epoch time \n";
                    }

                    $last_epoch_filter = $last_known_epochtime;

                }
                else {

                    if ($DEBUG) {
                        print
"DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur) \n";
                    }

                    $last_epoch_filter = $last_epoch_persection;

                }

            }

            # Open NMON file for reading
            if ( !open( FIC, $file ) ) {
                die(    "Error while trying to open NMON Source file '"
                      . $file
                      . "'" );
            }

            while ( defined( my $l = <FIC> ) ) {
                chomp $l;

                # Get timestamp"
                if ( ( rindex $l, "ZZZZ," ) > -1 ) {
                    ( my $t1, my $t2, my $timestamptmp1, my $timestamptmp2 ) =
                      split( ",", $l );
                    $timestamp = $timestamptmp2 . " " . $timestamptmp1;
                }

                # TOP Section"

                # Get and write csv header

                if ( $l =~ /^TOP,.PID/ ) {

                    my $x = $l;

                    # convert unwanted characters
                    $x =~ s/\%/pct_/g;

                    # $x =~ s/\W*//g;
                    $x =~ s/\/s/ps/g;    # /s  - ps
                    $x =~ s/\//s/g;      # / - s
                    $x =~ s/\(/_/g;
                    $x =~ s/\)/_/g;
                    $x =~ s/ /_/g;
                    $x =~ s/-/_/g;
                    $x =~ s/_KBps//g;
                    $x =~ s/_tps//g;
                    $x =~ s/[:,]*\s*$//;

                    $x =~ s/\+//g;
                    $x =~ s/\=0//g;

                    # Manage some fields we statically set
                    $x =~ s/TOP,//g;
                    $x =~ s/Time,//g;

                    my $write =
                        timestamp . ","
                      . type . ","
                      . OStype . ","
                      . serialnum . ","
                      . hostname . ","
                      . ZZZZ . ","
                      . logical_cpus . ","
                      . virtual_cpus . ","
                      . interval . ","
                      . snapshots . ","
                      . $x;

                    print( INSERT "$write\n" );
                    $count++;

                }

                # Get and write NMON section
                if (   ( ( rindex $l, "TOP," ) > -1 )
                    && ( length($timestamp) > 0 ) )
                {

                    ( my @line ) = split( ",", $l );
                    my $section = "TOP";

                    # Convert month pattern to month numbers (eg. %b to %m)
                    $timestamp =~ s/JAN/01/g;
                    $timestamp =~ s/FEB/02/g;
                    $timestamp =~ s/MAR/03/g;
                    $timestamp =~ s/APR/04/g;
                    $timestamp =~ s/MAY/05/g;
                    $timestamp =~ s/JUN/06/g;
                    $timestamp =~ s/JUL/07/g;
                    $timestamp =~ s/AUG/08/g;
                    $timestamp =~ s/SEP/09/g;
                    $timestamp =~ s/OCT/10/g;
                    $timestamp =~ s/NOV/11/g;
                    $timestamp =~ s/DEC/12/g;

     # Convert timestamp string to epoch time (from format: DD-MM-YYYY hh:mm:ss)
                    my ( $day, $month, $year, $hour, $min, $sec ) =
                      split /\W+/, $timestamp;
                    my $ZZZZ_epochtime =
                      timelocal( $sec, $min, $hour, $day, $month - 1, $year );

                    my $write =
                        '"'
                      . $ZZZZ_epochtime . '"' . "," . '"'
                      . $section . '"' . "," . '"'
                      . $OStype . '"' . "," . '"'
                      . $SN . '"' . "," . '"'
                      . $HOSTNAME . '"' . "," . '"'
                      . $timestamp . '"' . "," . '"'
                      . $logical_cpus . '"' . "," . '"'
                      . $virtual_cpus . '"' . "," . '"'
                      . $INTERVAL . '"' . "," . '"'
                      . $SNAPSHOTS . '"' . ","
                      . $line[1];
                    my $i = 3
                      ; ###########################################################################

                    while ( $i <= $#line ) {
                        $write = $write . ',"' . $line[$i] . '"';
                        $i     = $i + 1;
                    }

  # If in realtime mode, only extract events newer than the last known epochtime
                    if ( $realtime eq "True" ) {

                        if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                            print( INSERT $write . "\n" );
                            $count++;
                        }

                        else {

                            if ($DEBUG) {
                                print
"DEBUG, $key ignoring event $timestamp ( $ZZZZ_epochtime is lower than last known epoch time for this section $last_epoch_filter) \n";
                            }

                        }

                    }
                    elsif ( $colddata eq "True" || $fifo eq "True" ) {
                        print( INSERT $write . "\n" );
                        $count++;
                    }

                }

            }

            # If we wrote more than the header
            if ( $count >= 1 ) {

                if ( $sanity_check == 0 ) {

                    if (not $SILENT) {
                        print "$key section: Wrote $count line(s)\n";
                        print ID_REF "$key section: Wrote $count line(s)\n";
                    }

                    if ( $realtime eq "True" ) {

                        if ($DEBUG) {
                            print
"Per section write, Last epochtime is $ZZZZ_epochtime \n";
                        }

                        # Open keyref for writing in create mode
                        open( f, ">$keyref" );

                        # save configuration extraction
                        print f "last_epoch: $ZZZZ_epochtime \n";

                    }

                }

                else {
                    # Something happened, don't let bad file in place
                    unlink $BASEFILENAME;
                }

            }

            # Else remove the file without more explanations
            else {
                unlink $BASEFILENAME;
            }

        }    # end find the section

    }    # end foreach

###################################################""

####################################################################################################
#############		NMON UARG Section						############
####################################################################################################

    # UARG Section (specific)
    # Applicable for OStype AIX, Linux, Solaris or Unknown

    if (   $OStype eq "AIX"
        || $OStype eq "Linux"
        || $OStype eq "Solaris"
        || $OStype eq "Unknown" )
    {

        my $sanity_check = 0;

        foreach $key (@uarg_vars) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";

            # Open NMON file for reading
            if ( !open( FIC, $file ) ) {
                die(    "Error while trying to open NMON Source file '"
                      . $file
                      . "'" );
            }

            # If we find the section, enter the process
            if ( grep { /UARG,T/ } <FIC> ) {

                @rawdataheader = grep( /^UARG,\+Time,/, @nmon );
                if ( @rawdataheader < 1 ) {
                    $msg =
"WARN: hostname: $HOSTNAME :$key section data is not consistent: the data header could not be identified, dropping the section to prevent data inconsistency \n";
                    print "$msg";
                    print ID_REF "$msg";

                    $sanity_check = "1";

                }

                else {

                    unless ( open( INSERT, ">$BASEFILENAME" ) ) {
                        die("ERROR: Can not open /$BASEFILENAME\n");
                    }

                }

                # Open NMON file for reading
                if ( !open( FIC, $file ) ) {
                    die(    "Error while trying to open NMON Source file '"
                          . $file
                          . "'" );
                }

                # Initialize variables
                my $section   = "";
                my $timestamp = "";
                $count = 0;

                # Store last epochtime if in real time mode
                $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

                if ( $realtime eq "True" ) {

                    if ( -e $keyref ) {

                        open( keyref, "< $keyref" )
                          or die "ERROR: Can't open $keyref : $!";
                        while ( defined( my $l = <keyref> ) ) {
                            chomp $l;

                            # Get epoch time
                            if ( ( rindex $l, "last_epoch" ) > -1 ) {
                                ( my $t1, my $t2 ) =
                                  split( ": ", $l );
                                $last_epoch_persection = $t2;

                                if ($DEBUG) {
                                    print
"DEBUG, Last known timestamp for $key section is: $last_epoch_persection \n";
                                }
                            }

                        }

                    }

                    else {

                        if ($DEBUG) {
                            print
"DEBUG, no keyref for file for this $key section (searched for $keyref), no data or first execution \n";
                        }

                    }

                  # Define if we use global last epoch or per section last epoch
                    if ( not $last_epoch_persection ) {

                        if ($DEBUG) {
                            print
"DEBUG: no last epoch information were found for $key section, using global last epoch time \n";
                        }

                        $last_epoch_filter = $last_known_epochtime;

                    }
                    else {

                        if ($DEBUG) {
                            print
"DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur) \n";
                        }

                        $last_epoch_filter = $last_epoch_persection;

                    }

                }

                while ( defined( my $l = <FIC> ) ) {
                    chomp $l;

                    # Get timestamp"
                    if ( ( rindex $l, "ZZZZ," ) > -1 ) {
                        ( my $t1, my $t2, my $timestamptmp1, my $timestamptmp2 )
                          = split( ",", $l );
                        $timestamp = $timestamptmp2 . " " . $timestamptmp1;
                    }

                    # UARG Section"

                    # Get and write csv header

                    if ( $l =~ /^UARG,\+Time,/ ) {

                        my $x = $l;

                        # convert unwanted characters
                        $x =~ s/\%/pct_/g;

                        # $x =~ s/\W*//g;
                        $x =~ s/\/s/ps/g;    # /s  - ps
                        $x =~ s/\//s/g;      # / - s
                        $x =~ s/\(/_/g;
                        $x =~ s/\)/_/g;
                        $x =~ s/ /_/g;
                        $x =~ s/-/_/g;
                        $x =~ s/_KBps//g;
                        $x =~ s/_tps//g;
                        $x =~ s/[:,]*\s*$//;

                        $x =~ s/\+//g;
                        $x =~ s/\=0//g;

                        $x =~ s/\+Time/Time/g;

                        # Manage some fields we statically set
                        $x =~ s/UARG,//g;
                        $x =~ s/Time,//g;

                     # Specifically for UARG, set OS type based on header fields

                        if ( $l =~
/^UARG,\+Time,PID,PPID,COMM,THCOUNT,USER,GROUP,FullCommand/
                          )
                        {

                            my $write =
                                timestamp . ","
                              . type . ","
                              . OStype . ","
                              . serialnum . ","
                              . hostname . ","
                              . ZZZZ . ","
                              . logical_cpus . ","
                              . virtual_cpus . ","
                              . interval . ","
                              . snapshots . ","
                              . PID . ","
                              . PPID . ","
                              . COMM . ","
                              . THCOUNT . ","
                              . USER . ","
                              . GROUP . ","
                              . FullCommand;

                            print( INSERT "$write\n" );
                            $count++;

                        }

                        elsif ( $l =~ /^UARG,\+Time,PID,ProgName,FullCommand/ )
                        {

                            my $write =
                                timestamp . ","
                              . type . ","
                              . OStype . ","
                              . serialnum . ","
                              . hostname . ","
                              . ZZZZ . ","
                              . logical_cpus . ","
                              . virtual_cpus . ","
                              . interval . ","
                              . snapshots . ","
                              . PID . ","
                              . ProgName . ","
                              . FullCommand;

                            print( INSERT "$write\n" );
                            $count++;

                        }

                    }

                    # Get and write NMON section
                    if (   ( ( rindex $l, "UARG," ) > -1 )
                        && ( length($timestamp) > 0 ) )
                    {

                        ( my @line ) = split( ",", $l );
                        my $section = "UARG";

                        # Convert month pattern to month numbers (eg. %b to %m)
                        $timestamp =~ s/JAN/01/g;
                        $timestamp =~ s/FEB/02/g;
                        $timestamp =~ s/MAR/03/g;
                        $timestamp =~ s/APR/04/g;
                        $timestamp =~ s/MAY/05/g;
                        $timestamp =~ s/JUN/06/g;
                        $timestamp =~ s/JUL/07/g;
                        $timestamp =~ s/AUG/08/g;
                        $timestamp =~ s/SEP/09/g;
                        $timestamp =~ s/OCT/10/g;
                        $timestamp =~ s/NOV/11/g;
                        $timestamp =~ s/DEC/12/g;

                        # For AIX

# In this section, we statically expect 7 fields: PID,PPID,COMM,THCOUNT,USER,GROUP,FullCommand
# The FullCommand may be very problematic as it may almost contain any kind of char, comma included
# This field will have " separator added

                        if ( $l =~
m/^UARG\,T\d+\,\s*([0-9]*)\s*\,\s*([0-9]*)\s*\,\s*([a-zA-Z\-\/\_\:\.0-9]*)\s*\,\s*([0-9]*)\s*\,\s*([a-zA-Z\-\/\_\:\.0-9]*\s*)\,\s*([a-zA-Z\-\/\_\:\.0-9]*)\s*\,(.+)/
                          )
                        {

     # Convert timestamp string to epoch time (from format: DD-MM-YYYY hh:mm:ss)
                            my ( $day, $month, $year, $hour, $min, $sec ) =
                              split /\W+/, $timestamp;
                            my $ZZZZ_epochtime =
                              timelocal( $sec, $min, $hour, $day,
                                $month - 1, $year );

                            $PID         = $1;
                            $PPID        = $2;
                            $COMM        = $3;
                            $THCOUNT     = $4;
                            $USER        = $5;
                            $GROUP       = $6;
                            $FullCommand = $7;

                            $x =
                                '"' . ""
                              . $PID . "" . '","' . ""
                              . $PPID . "" . '","' . ""
                              . $COMM . "" . '","' . ""
                              . $THCOUNT . "" . '","' . ""
                              . $USER . "" . '","' . ""
                              . $GROUP . "" . '","' . ""
                              . $FullCommand . '"';

                            my $write =
                                '"'
                              . $ZZZZ_epochtime . '"' . "," . '"'
                              . $section . '"' . "," . '"'
                              . $OStype . '"' . "," . '"'
                              . $SN . '"' . "," . '"'
                              . $HOSTNAME . '"' . "," . '"'
                              . $timestamp . '"' . "," . '"'
                              . $logical_cpus . '"' . "," . '"'
                              . $virtual_cpus . '"' . "," . '"'
                              . $INTERVAL . '"' . "," . '"'
                              . $SNAPSHOTS . '"' . ","
                              . $x;

  # If in realtime mode, only extract events newer than the last known epochtime
                            if ( $realtime eq "True" ) {

                                if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                                    print( INSERT $write . "\n" );
                                    $count++;

                                }

                                else {

                                    if ($DEBUG) {
                                        print
"DEBUG, $key ignoring event $timestamp ( $ZZZZ_epochtime is lower than last known epoch time for this section $last_epoch_filter) \n";
                                    }

                                }
                            }
                            elsif ( $colddata eq "True" ) {
                                print( INSERT $write . "\n" );
                                $count++;
                            }

                        }

                        # For Linux / Solaris

# In this section, we statically expect 3 fields: PID,ProgName,FullCommand
# The FullCommand may be very problematic as it may almost contain any kind of char, comma included
# Let's separate groups and insert " delimiter

                        if ( $l =~
m/^UARG\,T\d+\,([0-9]*)\,([a-zA-Z\-\/\_\:\.0-9]*)\,(.+)/
                          )
                        {

     # Convert timestamp string to epoch time (from format: DD-MM-YYYY hh:mm:ss)
                            my ( $day, $month, $year, $hour, $min, $sec ) =
                              split /\W+/, $timestamp;
                            my $ZZZZ_epochtime =
                              timelocal( $sec, $min, $hour, $day,
                                $month - 1, $year );

                            $PID         = $1;
                            $ProgName    = $2;
                            $FullCommand = $3;

                            $x =
                                '"' . ""
                              . $PID . "" . '","' . ""
                              . $ProgName . "" . '","' . ""
                              . $FullCommand . "" . '"';

                            my $write =
                                '"'
                              . $ZZZZ_epochtime . '"' . "," . '"'
                              . $section . '"' . "," . '"'
                              . $OStype . '"' . "," . '"'
                              . $SN . '"' . "," . '"'
                              . $HOSTNAME . '"' . "," . '"'
                              . $timestamp . '"' . "," . '"'
                              . $logical_cpus . '"' . "," . '"'
                              . $virtual_cpus . '"' . "," . '"'
                              . $INTERVAL . '"' . "," . '"'
                              . $SNAPSHOTS . '"' . ","
                              . $x;

  # If in realtime mode, only extract events newer than the last known epochtime
                            if ( $realtime eq "True" ) {

                                if ( $ZZZZ_epochtime > $last_known_epochtime ) {

                                    print( INSERT $write . "\n" );
                                    $count++;
                                }
                            }
                            elsif ( $colddata eq "True" || $fifo eq "True" ) {
                                print( INSERT $write . "\n" );
                                $count++;
                            }

                        }

                    }

                }

                # If we wrote more than the header
                if ( $count >= 1 ) {

                    if ( $sanity_check == 0 ) {

                        if (not $SILENT) {
                            print "$key section: Wrote $count line(s)\n";
                            print ID_REF "$key section: Wrote $count line(s)\n";
                        }

                        if ( $realtime eq "True" ) {

                            if ($DEBUG) {
                                print
"Per section write, Last epochtime is $ZZZZ_epochtime \n";
                            }

                            # Open keyref for writing in create mode
                            open( f, ">$keyref" );

                            # save configuration extraction
                            print f "last_epoch: $ZZZZ_epochtime \n";

                        }

                    }

                    else {
                        # Something happened, don't let bad file in place
                        unlink $BASEFILENAME;
                    }

                }

                # Else remove the file without more explanations
                else {
                    unlink $BASEFILENAME;
                }

            }    # end find the section

        }    # end foreach

    }

###################################################""

####################################################################################################
#############		NMON Sections with variable fields (eg. with devices)		############
####################################################################################################

    ###################################################

    # Dynamic Sections, manage up to 20 sections, 3000 devices

    foreach $key (@dynamic_vars1) {

        # First pass with standard keys
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
        $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

        &variable_sections_insert($key);
        $now = time();
        $now = $now - $start;

    }

    foreach $mainkey (@dynamic_vars1) {

        # Search for supplementary sections
        $init = 0;

        do {

            $init = $init + 1;

            $key = join '', $mainkey, $init;

            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        } while ( $init < 20 );

    }

    # Dynamic Sections with no increment

    foreach $key (@dynamic_vars2) {

        # First pass with standard keys
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
        $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

        &variable_sections_insert($key);
        $now = time();
        $now = $now - $start;

    }

    # Disks extended stats

    foreach $key (@disk_extended_section) {

        # First pass with standard keys
        $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
        $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

        &variable_sections_insert($key);
        $now = time();
        $now = $now - $start;

    }

    # AIX Specific sections, run this for OStype AIX or unknown

    if ( $OStype eq "AIX" || $OStype eq "Unknown" ) {

        foreach $key (@AIX_dynamic_various) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }

        foreach $key (@AIX_WLM) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }

    }

    # Solaris Specific sections, run this for OStype Solaris or unknown

    # WLM Stats

    if ( $OStype eq "Solaris" || $OStype eq "Unknown" ) {

        foreach $key (@solaris_WLM) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &solaris_wlm_section_fn($key);
            $now = time();
            $now = $now - $start;

        }

        # VxVM volumes

        foreach $key (@solaris_VxVM) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }

        # Other dynamics

        foreach $key (@solaris_dynamic_various) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }

        # nmon external with transposition

        foreach $key (@nmon_external_transposed) {
            $BASEFILENAME =
"$OUTPUT_DIR/${HOSTNAME}_${nmon_day}_${nmon_month}_${nmon_year}_${nmon_hour}${nmon_minute}${nmon_second}_${key}_${bytes}_${csv_timestamp}.nmon.csv";
            $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

            &variable_sections_insert($key);
            $now = time();
            $now = $now - $start;

        }

    }

##########################
    # Convert csv data to kv log
##########################

    # Each csv file must be merged to main log
    @data = ("$OUTPUT_DIR/*.csv");

    # destination
    my $outfile = "$OUTPUTFINAL_DIR/nmon_perfdata.log";

    # Enter loop
    foreach $key (@data) {

        @files = glob($key);

        foreach $file (@files) {
            if ( -f $file ) {
                &csv2kv( $file, $outfile );
                unlink $file;
            }
        }
    }


    if ($use_splunk_http) {
        # Finally Stream to Splunk HEC in batch
        &stream_to_splunk_http();
    }

#############################################
#############  Main Program End 	############
#############################################

    # Close Temp NMON File
    close(INSERT);

    # Delete temp nmon file
    unlink("$FILENAME");

    # Show elapsed time
    my $t_end = [Time::HiRes::gettimeofday];
    print "Elapsed time was: ",
      Time::HiRes::tv_interval( $t_start, $t_end ) . " seconds \n";

    # Save Elapsed to ID_REF
    print ID_REF "Elapsed time was: ",
      Time::HiRes::tv_interval( $t_start, $t_end ) . " seconds \n";

}
exit(0);

############################################
#############  Subroutines 	############
############################################

##################################################################
## csv to key=value format
##################################################################

sub csv2kv {

    my $infile  = $_[0];
    my $outfile = $_[1];

    if ( -e $infile ) {

        # Open infile for reading
        unless ( open( FH, "< $infile" ) ) {
            die("ERROR: Can not open /$infile for reading\n");
        }
        my @lines = <FH>;
        close FH;

        if (not $NO_LOCAL_LOG) {
            # Open outfile for writing
            unless (open(INSERT, ">> $outfile")) {
                die("ERROR: Can not open /$outfile for writting\n");
            }
        }

        # for Splunk HEC only
        unless ( open( SPLUNK_HEC, ">> $SPLUNK_HEC_BATCHFILE" ) ) {
            die("ERROR: Can not open /$SPLUNK_HEC_BATCHFILE for writting\n");
        }

        my $count = 0;
        my @header;
        my @event;
        my $line;
        my $hdcount;
        my $loopvariable;
        my $kvdata;
        my $http_data;

        foreach $line (@lines) {
            if ( $count == 0 ) {
                chomp $line;
                @header = split /,/, $line;
                $count = $count = 1;
            }
            else {
                chomp $line;
                @event   = split /,/, $line;
                $count   = $count + 1;
                $hdcount = 0;

                foreach $loopvariable (@event) {
                    if ( $loopvariable eq "" ) {
                        $hdcount = $hdcount + 1;
                        last;
                    }

                    if (not $NO_LOCAL_LOG) {
                        print INSERT $header[$hdcount] . "=" . $loopvariable . " ";
                    }

                    # for Splunk HEC
                    if ($use_splunk_http) {
                        $kvdata =
                            $kvdata
                          . $header[$hdcount] . "="
                          . $loopvariable . " ";
                    }

                    $hdcount = $hdcount + 1;
                }
                if (not $NO_LOCAL_LOG) {
                    print INSERT "\n";
                }

                # For Splunk HEC
                if ($use_splunk_http) {
                    #$kvdata =~ s/"/\\"/g;
                    my $timestamp = "";

                    if ( $kvdata =~ /timestamp=\"(\d*)\"/ ) {
                        $timestamp = $1;
                    }
                    else {
                        print
"failed to parse timestamp before streaming to http, applying now as the timestamp\n";
                        $timestamp = time();
                    }

                    $kvdata =~ s/"/\\"/g;
                    $kvdata = "{\"time\": \"$timestamp\", \"sourcetype\": \"nmon_data:fromhttp\", \"event\": \"$kvdata\"}\n";

                    print SPLUNK_HEC "$kvdata";

                    # Empty for next loop
                    $kvdata    = "";
                    $timestamp = "";

                }

            }

        }

    }    # end main if

}

# Stream to Splunk HEC in batch
sub stream_to_splunk_http () {

    # Stream to http
    $curl = `curl -s -k -H "Authorization: Splunk $SPLUNK_HTTP_TOKEN" $SPLUNK_HTTP_URL -d \@$SPLUNK_HEC_BATCHFILE 2>&1 /dev/null`;

    if ($DEBUG) {
        print
"DEBUG, sending: curl -s -k -H \"Authorization: Splunk $SPLUNK_HTTP_TOKEN\" $SPLUNK_HTTP_URL -d \@$SPLUNK_HEC_BATCHFILE'\n";
    }

    if ( -e $SPLUNK_HEC_BATCHFILE ) {
                unlink $SPLUNK_HEC_BATCHFILE;
    }

}

##################################################################
## Configuration Extraction
##################################################################

sub config_extract {

    if (not $NO_LOCAL_LOG) {
        # Open for writing in append mode
        unless (open(INSERT, ">>$BASEFILENAME")) {
            die("ERROR: ERROR: Can not open /$BASEFILENAME\n");
        }
    }

    # Splunk HEC
    my $config_output_tmp = "$NMON_VAR/nmon_configdata_splunkhec.tmp";
    my $config_output_final = "$NMON_VAR/nmon_configdata_splunkhec.log";

     if ($use_splunk_http) {
        unless (open(INSERT_HEC_TMP, ">$config_output_tmp")) {
            die("ERROR: ERROR: Can not open $config_output_tmp\n");
        }
        unless (open(INSERT_HEC, ">$config_output_final")) {
            die("ERROR: ERROR: Can not open $config_output_final\n");
        }
    }

    # Initialize variables
    my $section      = "CONFIG";
    my $time         = "";
    my $date         = "";
    my $hostnameT    = "Unknown";
    my $SerialNumber = "Unknown";
    $count     = 0;
    $BBB_count = 0;

    # Get nmon/server settings (search string, return column, delimiter)
    $AIXVER   = &get_setting( "AIX",      2, "," );

    # Allow hostname os
    if ($USE_FQDN) {
        chomp( $HOSTNAME = `hostname -f` );
    }
    else {
        $HOSTNAME = &get_setting( "host", 2, "," );
    }

    $DATE     = &get_setting( "AAA,date", 2, "," );
    $TIME     = &get_setting( "AAA,time", 2, "," );

    # for AIX
    if ( $AIXVER ne "-1" ) {
        $SN = &get_setting( "systemid", 4, "," );
        $SN = ( split( /\s+/, $SN ) )[0];    # "systemid IBM,SN ..."
    }

    # for Power Linux
    else {
        $SN = &get_setting( "serial_number", 4, "," );
        $SN = ( split( /\s+/, $SN ) )[0];    # "serial_number=IBM,SN ..."
    }

    # undeterminated
    if ( $SN eq "-1" ) {
        $SN = $HOSTNAME;
    }
    elsif ( $SN eq "" ) {
        $SN = $HOSTNAME;
    }

    # write event header

    my $colon = '"';

    my $write =
        "timestamp=$colon"
      . $STARTING_EPOCHTIME
      . "$colon, date=$colon"
      . $DATE . ":"
      . $TIME
      . "$colon, host=$colon"
      . $HOSTNAME
      . "$colon, serialnum=$colon"
      . $SN
      . "$colon, configuration_content=$colon";

    if (not $NO_LOCAL_LOG) {
        print(INSERT "$write\n");
    }

    if ($use_splunk_http) {
        print(INSERT_HEC_TMP "$write\n");
    }

    $count++;

    # Open NMON file for reading
    if ( !open( FIC, $file ) ) {
        die( "ERROR: while trying to open NMON Source file '" . $file . "'" );
    }

    while ( defined( my $l = <FIC> ) ) {
        chomp $l;

        # CONFIG Section"

        if ( $l =~ /^AAA/ ) {

            my $x = $l;

            # Manage some fields we statically set
            $x =~ s/CONFIG,//g;
            $x =~ s/Time,//g;

            my $write = $x;

            if (not $NO_LOCAL_LOG) {
                print(INSERT "$write\n");
            }

            if ($use_splunk_http) {
                print(INSERT_HEC_TMP "$write\n");
            }

            $count++;

        }

        if ( $l =~ /^BBB/ ) {

            my $x = $l;

            # Manage some fields we statically set
            $x =~ s/CONFIG,//g;
            $x =~ s/Time,//g;

            my $write = $x;

            if (not $NO_LOCAL_LOG) {
                print(INSERT "$write\n");
            }

            if ($use_splunk_http) {
                print(INSERT_HEC_TMP "$write\n");
            }

            $count++;
            $BBB_count++;

        }

    }

    if (not $NO_LOCAL_LOG) {
        # print terminator
        print(INSERT "$colon");
        close INSERT;
    }

    if ($use_splunk_http) {

        print(INSERT_HEC_TMP "$colon");
        close INSERT_HEC_TMP;

        # Insert the HEC header
        print INSERT_HEC "{\"sourcetype\": \"nmon_config:fromhttp\", \"event\": \"";

        open my $origin, $config_output_tmp or die "Could not open $config_output_tmp: $!";

        while (my $line = <$origin>) {
            $line =~ s/\'/ /g;
            $line =~ s/\"/\\"/g;
            $line = "$line\\n";
            print INSERT_HEC $line;
        }

        print INSERT_HEC '"}';

        if ($DEBUG) {
            print
"DEBUG, sending: curl -s -k -H \"Authorization: Splunk $SPLUNK_HTTP_TOKEN\" $SPLUNK_HTTP_URL -d \@$config_output_final'\n";
        }

        # Stream to http
        $curl = `curl -s -k -H "Authorization: Splunk $SPLUNK_HTTP_TOKEN" $SPLUNK_HTTP_URL -d \@$config_output_final 2>&1 /dev/null`;

        close INSERT_HEC;

        if ( -e $config_output_tmp ) {
            unlink $config_output_tmp;
        }

        if ( -e $config_output_final ) {
            unlink $config_output_final;
        }

    }

# If we extracted at least 10 lines of BBB data, estimate we successfully extracted it
    if ( $BBB_count > 10 ) {

        if ( -e $BBB_FLAG ) {

            unlink $BBB_FLAG;

        }

    }

    else {

        open( BBB_FLAG, ">$BBB_FLAG" );
        print BBB_FLAG "BBB_status KO";

        print "CONFIG section: BBB section not extracted (no data yet) \n";

        print ID_REF
          "CONFIG section: BBB section not extracted (no data yet) \n";

    }

    print "$key section: Wrote $count lines\n";
    print ID_REF "$key section: Wrote $count lines\n";

    # Open CONFIG_REF for writing in create mode
    open( CONFIG_REF, ">$CONFIG_REF" );

    # save configuration extraction
    print CONFIG_REF "$HOSTNAME: $time_epoch \n";

}

##################################################################
## Extract data for Static fields
##################################################################

sub static_sections_insert {

    my ($nmon_var) = @_;
    my $table = lc($nmon_var);

    my @rawdata;
    my $x;
    my @cols;
    my $TS;
    my $n;
    my $sanity_check                  = 0;
    my $sanity_check_timestampfailure = 0;
    $count = 0;

    if ( $realtime eq "True" ) {

        if ( -e $keyref ) {

            open( keyref, "< $keyref" )
              or die "ERROR: Can't open $keyref : $!";
            while ( defined( my $l = <keyref> ) ) {
                chomp $l;

                # Get epoch time
                if ( ( rindex $l, "last_epoch" ) > -1 ) {
                    ( my $t1, my $t2 ) =
                      split( ": ", $l );
                    $last_epoch_persection = $t2;

                    if ($DEBUG) {
                        print
"DEBUG, Last known timestamp for $key section is: $last_epoch_persection \n";
                    }
                }

            }

        }

        else {

            if ($DEBUG) {
                print
"DEBUG, no keyref for file for this $key section (searched for $keyref), no data or first execution \n";
            }

        }

        # Define if we use global last epoch or per section last epoch
        if ( not $last_epoch_persection ) {

            if ($DEBUG) {
                print
"DEBUG: no last epoch information were found for $key section, using global last epoch time \n";
            }

            $last_epoch_filter = $last_known_epochtime;

        }
        else {

            if ($DEBUG) {
                print
"DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur) \n";
            }

            $last_epoch_filter = $last_epoch_persection;

        }

    }

# Filter rawdata for this section, CPUnn has a special case that contains dynamic number of sub-sections
    if ( $nmon_var eq "CPUnn" ) {
        @rawdata = grep( /^CPU\d*,/, @nmon );
    }
    else {
        @rawdata = grep( /^$nmon_var,/, @nmon );
    }

    if ( @rawdata < 1 ) { return (1); }
    else {

        # Focus on the header, manage CPUnn case
        if ( $nmon_var eq "CPUnn" ) {
            @rawdataheader = grep( /^CPU\d*,([^T].+),/, @nmon );
        }
        else {
            @rawdataheader = grep( /^$nmon_var,([^T].+),/, @nmon );
        }

        if ( @rawdataheader < 1 ) {
            $msg =
"WARN: hostname: $HOSTNAME :$key section data is not consistent: the data header could not be identified, dropping the section to prevent data inconsistency \n";
            print "$msg";
            print ID_REF "$msg";

            $sanity_check = "1";

        }

        else {

            unless ( open( INSERT, ">$BASEFILENAME" ) ) {
                die("ERROR: Can not open /$BASEFILENAME\n");
            }

        }

    }

    # Sort rawdata
    @rawdata = sort(@rawdata);

    @cols = split( /,/, $rawdata[0] );
    $x = join( ",", @cols[ 2 .. @cols - 1 ] );
    $x =~ s/\%/_PCT/g;
    $x =~ s/\(MB\)/_MB/g;
    $x =~ s/-/_/g;
    $x =~ s/ /_/g;
    $x =~ s/__/_/g;
    $x =~ s/,_/,/g;
    $x =~ s/_,/,/g;
    $x =~ s/^_//;
    $x =~ s/_$//;

    # Count the number fields in header
    my @c                 = $x =~ /,/g;
    my $fieldsheadercount = @c;

    print INSERT (
qq|timestamp,type,serialnum,hostname,OStype,logical_cpus,virtual_cpus,ZZZZ,interval,snapshots,$x\n|
    );

# For CPUnn case, filter on perf data only (multiple headers are present in rawdata)
    if ( $nmon_var eq "CPUnn" ) {
        @rawdata = grep( /^CPU\d*,T.+,/, @nmon );
    }

    $n     = @cols;
    $n     = $n - 1;    # number of columns -1

# Define the starting line to read (exclusion of csv header)
# For CPUnn, we don't need to filter the header as we already filtered on perf data

    if ( $nmon_var eq "CPUnn" ) {
        $startline = 0;
    }
    else {
        $startline = 1;
    }

    for ( $i = $startline ; $i < @rawdata ; $i++ ) {

        $TS = $UTC_START + $INTERVAL * ($i);

        @cols = split( /,/, $rawdata[$i] );
        $x = join( ",", @cols[ 2 .. $n ] );
        $x =~ s/,,/,-1,/g;    # replace missing data ",," with a ",-1,"

        my @c              = $x =~ /,/g;
        my $fieldsrawcount = @c;

        # Double quotes all CSV values
        $x =~ s/,/\",\"/g;
        $x =~ s/($)/\"/g;
        $x =~ s/(^)/\"/g;

        # section dynamic name
        $datatype = @cols[0];

        if ( $fieldsrawcount != $fieldsheadercount ) {

            $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: $fieldsrawcount fields in data, $fieldsheadercount fields in header, extra fields detected (more fields in data than header), dropping this section to prevent data inconsistency \n";
            print "$msg";
            print ID_REF "$msg";

            $sanity_check = "1";

        }

# If the timestamp could not be found, there is a data anomaly and the section is not consistent
        if ( not $DATETIME{ $cols[1] } ) {

            $sanity_check                  = "1";
            $sanity_check_timestampfailure = "1";

        }

        # If sanity check is ok, write data
        if ( $sanity_check == 0 ) {

            $timestamp = $DATETIME{ @cols[1] };

     # Convert timestamp string to epoch time (from format: YYYY-MM-DD hh:mm:ss)
            my ( $year, $month, $day, $hour, $min, $sec ) = split /\W+/,
              $timestamp;
            my $ZZZZ_epochtime =
              timelocal( $sec, $min, $hour, $day, $month - 1, $year );

            # Write only new data if in realtime mode

            if ( $realtime eq "True" ) {

                if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                    print INSERT (
qq|"$ZZZZ_epochtime","$datatype","$SN","$HOSTNAME","$OStype","$logical_cpus","$virtual_cpus","$DATETIME{@cols[1]}","$INTERVAL","$SNAPSHOTS",$x\n|
                    );
                    $count++;

                }

                else {

                    if ($DEBUG) {
                        print
"DEBUG, $key ignoring event $DATETIME{@cols[1]} ( $ZZZZ_epochtime is lower than last known epoch time for this section $last_epoch_filter) \n";
                    }

                }

            }

            elsif ( $colddata eq "True" || $fifo eq "True" ) {

                print INSERT (
qq|"$ZZZZ_epochtime","$datatype","$SN","$HOSTNAME","$OStype","$logical_cpus","$virtual_cpus","$DATETIME{@cols[1]}","$INTERVAL","$SNAPSHOTS",$x\n|
                );
                $count++;

            }

        }

    }
    print INSERT (qq||);

    # If sanity check has failed, remove data
    if ( $sanity_check != 0 && $sanity_check_timestampfailure != 0 ) {

        $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: Detected anomalies in events timestamp, dropping this section to prevent data inconsistency \n";
        print "$msg";
        print ID_REF "$msg";

        unlink $BASEFILENAME;
    }

    elsif ( $sanity_check != 0 ) {

        unlink $BASEFILENAME

    }

    else {
        if ( $count >= 1 ) {

            if (not $SILENT) {
                print "$key section: Wrote $count lines\n";
                print ID_REF "$key section: Wrote $count lines\n";
            }

            if ( $realtime eq "True" ) {

                if ($DEBUG) {
                    print
                      "Per section write, Last epochtime is $ZZZZ_epochtime \n";
                }

                # Open keyref for writing in create mode
                open( f, ">$keyref" );

                # save configuration extraction
                print f "last_epoch: $ZZZZ_epochtime \n";

            }

        }

        else {
            # Hey, only a header ! Don't keep empty files please
            unlink $BASEFILENAME;
        }
    }

}    # End Insert

##################################################################
## Extract data for Variable fields
##################################################################

sub variable_sections_insert {

    my ($nmon_var) = @_;
    my $table = lc($nmon_var);

    my @rawdata;
    my $x;
    my $j;
    my @cols;
    my $TS;
    my $n;
    my @devices;
    my $sanity_check                  = 0;
    my $sanity_check_timestampfailure = 0;
    $count = 0;

    if ( $realtime eq "True" ) {

        if ( -e $keyref ) {

            open( keyref, "< $keyref" )
              or die "ERROR: Can't open $keyref : $!";
            while ( defined( my $l = <keyref> ) ) {
                chomp $l;

                # Get epoch time
                if ( ( rindex $l, "last_epoch" ) > -1 ) {
                    ( my $t1, my $t2 ) =
                      split( ": ", $l );
                    $last_epoch_persection = $t2;

                    if ($DEBUG) {
                        print
"DEBUG, Last known timestamp for $key section is: $last_epoch_persection \n";
                    }
                }

            }

        }

        else {

            if ($DEBUG) {
                print
"DEBUG, no keyref for file for this $key section (searched for $keyref), no data or first execution \n";
            }

        }

        # Define if we use global last epoch or per section last epoch
        if ( not $last_epoch_persection ) {

            if ($DEBUG) {
                print
"DEBUG: no last epoch information were found for $key section, using global last epoch time (gaps in data may occur if not the first time we run) \n";
            }

            $last_epoch_filter = $last_known_epochtime;

        }
        else {

            if ($DEBUG) {
                print
"DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur) \n";
            }

            $last_epoch_filter = $last_epoch_persection;

        }

    }

    @rawdata = grep( /^$nmon_var,/, @nmon );

    if ( @rawdata < 1 ) { return (1); }
    else {

        @rawdataheader = grep( /^$nmon_var,([^T].+),/, @nmon );
        if ( @rawdataheader < 1 ) {
            $msg =
"WARN: hostname: $HOSTNAME :$key section data is not consistent: the data header could not be identified, dropping the section to prevent data inconsistency \n";
            print "$msg";
            print ID_REF "$msg";

        }

        else {

            unless ( open( INSERT, ">$BASEFILENAME" ) ) {
                die("ERROR: Can not open /$BASEFILENAME\n");
            }

        }

    }

    @rawdata = sort(@rawdata);

    $rawdata[0] =~ s/\%/_PCT/g;
    $rawdata[0] =~ s/\(/_/g;
    $rawdata[0] =~ s/\)/_/g;
    $rawdata[0] =~ s/ /_/g;
    $rawdata[0] =~ s/__/_/g;
    $rawdata[0] =~ s/,_/,/g;

    @devices = split( /,/, $rawdata[0] );

    print INSERT (
qq|timestamp,type,serialnum,hostname,OStype,interval,snapshots,ZZZZ,device,value|
    );

    # Count the number fields in header
    my $header =
"timestamp,type,serialnum,hostname,OStype,interval,snapshots,ZZZZ,device,value";
    my @c                 = $header =~ /,/g;
    my $fieldsheadercount = @c;

    #print "\n COUNT IS $fieldsheadercount \n";

    $n = @rawdata;
    $n--;
    for ( $i = 1 ; $i < @rawdata ; $i++ ) {

        $TS = $UTC_START + $INTERVAL * ($i);
        $rawdata[$i] =~ s/,$//;
        @cols = split( /,/, $rawdata[$i] );

        $timestamp = $DATETIME{ $cols[1] };

     # Convert timestamp string to epoch time (from format: YYYY-MM-DD hh:mm:ss)
        my ( $year, $month, $day, $hour, $min, $sec ) = split /\W+/, $timestamp;

        if ( $month == 0 ) {
            print
"ERROR, section $key has failed to identify the timestamp of these data, affecting current timestamp which may be inaccurate\n";
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst )
              = localtime(time);
            $month = $mon;
            $day   = $mday;
        }

        my $ZZZZ_epochtime =
          timelocal( $sec, $min, $hour, $day, $month - 1, $year );

        # Write only new data if in realtime mode

        if ( $realtime eq "True" ) {

            if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                print INSERT (
qq|\n"$ZZZZ_epochtime","$key","$SN","$HOSTNAME","$OStype","$INTERVAL","$SNAPSHOTS","$DATETIME{$cols[1]}","$devices[2]","$cols[2]"|
                );

                $count++;

            }

            else {

                if ($DEBUG) {
"DEBUG, $key ignoring event $DATETIME{@cols[1]} ( $ZZZZ_epochtime is lower than last known epoch time for this section $last_epoch_filter) \n";
                }

            }

        }

        elsif ( $colddata eq "True" || $fifo eq "True" ) {

            print INSERT (
qq|\n"$ZZZZ_epochtime","$key","$SN","$HOSTNAME","$OStype","$INTERVAL","$SNAPSHOTS","$DATETIME{$cols[1]}","$devices[2]","$cols[2]"|
            );

            $count++;

        }

        for ( $j = 3 ; $j < @cols ; $j++ ) {

            $finaldata =
"$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[$j],$cols[$j]";

# If the timestamp could not be found, there is a data anomaly and the section is not consistent
            if ( not $DATETIME{ $cols[1] } ) {

                $sanity_check                  = "1";
                $sanity_check_timestampfailure = "1";

            }

            # Count the number fields in data
            my @c              = $finaldata =~ /,/g;
            my $fieldsrawcount = @c;

            #print "\n COUNT IS $fieldsrawcount \n";

            if ( $fieldsrawcount != $fieldsheadercount ) {

                $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: $fieldsrawcount fields in data, $fieldsheadercount fields in header, extra fields detected (more fields in data than header), dropping this section to prevent data inconsistency \n";
                print "$msg";
                print ID_REF "$msg";

                $sanity_check = "1";

            }

            # If sanity check has not failed, write data
            if ( $sanity_check != "1" ) {

                $timestamp = $DATETIME{ $cols[1] };

     # Convert timestamp string to epoch time (from format: YYYY-MM-DD hh:mm:ss)
                my ( $year, $month, $day, $hour, $min, $sec ) = split /\W+/,
                  $timestamp;
                my $ZZZZ_epochtime =
                  timelocal( $sec, $min, $hour, $day, $month - 1, $year );

                # Write only new data if in realtime mode

                if ( $realtime eq "True" ) {

                    if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                        print INSERT (
qq|\n"$ZZZZ_epochtime","$key","$SN","$HOSTNAME","$OStype","$INTERVAL","$SNAPSHOTS","$DATETIME{$cols[1]}","$devices[$j]","$cols[$j]"|
                        );
                        $count++;
                    }

                }

                elsif ( $colddata eq "True" || $fifo eq "True" ) {

                    print INSERT (
qq|\n"$ZZZZ_epochtime","$key","$SN","$HOSTNAME","$OStype","$INTERVAL","$SNAPSHOTS","$DATETIME{$cols[1]}","$devices[$j]","$cols[$j]"|
                    );
                    $count++;
                }

            }

        }
        if ( $i < $n ) { print INSERT (""); }
    }
    print INSERT (qq||);

    # If sanity check has failed, remove data
    if ( $sanity_check != 0 && $sanity_check_timestampfailure != 0 ) {

        $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: Detected anomalies in events timestamp, dropping this section to prevent data inconsistency \n";
        print "$msg";
        print ID_REF "$msg";

        unlink $BASEFILENAME;
    }

    elsif ( $sanity_check != 0 ) {

        unlink $BASEFILENAME

    }

    else {
        if ( $count >= 1 ) {

            if (not $SILENT) {
                print "$key section: Wrote $count lines\n";
                print ID_REF "$key section: Wrote $count lines\n";
            }

            if ( $realtime eq "True" ) {

                if ($DEBUG) {
                    print
                      "Per sectoon write, Last epochtime is $ZZZZ_epochtime \n";
                }

                # Open keyref for writing in create mode
                open( f, ">$keyref" );

                # save configuration extraction
                print f "last_epoch: $ZZZZ_epochtime \n";

            }

        }
        else {
            # Hey, only a header ! Don't keep empty files please
            unlink $BASEFILENAME;
        }
    }

}    # End Insert

#################################################################################################
# Specific Solaris version, add logical_cpus values to allow easy WLM CPU conversion statistics #
#################################################################################################

sub solaris_wlm_section_fn {

    my ($nmon_var) = @_;
    my $table = lc($nmon_var);

    my @rawdata;
    my $x;
    my $j;
    my @cols;
    my $TS;
    my $n;
    my @devices;
    my $sanity_check                  = 0;
    my $sanity_check_timestampfailure = 0;
    $count = 0;

    # Store last epochtime if in real time mode
    $keyref = "$HOSTNAME_VAR/" . "${HOSTNAME}.${key}_lastepoch.txt";

    if ( $realtime eq "True" ) {

        if ( -e $keyref ) {

            open( keyref, "< $keyref" )
              or die "ERROR: Can't open $keyref : $!";
            while ( defined( my $l = <keyref> ) ) {
                chomp $l;

                # Get epoch time
                if ( ( rindex $l, "last_epoch" ) > -1 ) {
                    ( my $t1, my $t2 ) =
                      split( ": ", $l );
                    $last_epoch_persection = $t2;

                    if ($DEBUG) {
                        print
"DEBUG, Last known timestamp for $key section is: $last_epoch_persection \n";
                    }
                }

            }

        }

        else {

            if ($DEBUG) {
                print
"DEBUG, no keyref for file for this $key section (searched for $keyref), no data or first execution \n";
            }

        }

        # Define if we use global last epoch or per section last epoch
        if ( not $last_epoch_persection ) {

            if ($DEBUG) {
                print
"DEBUG: no last epoch information were found for $key section, using global last epoch time (gaps in data may occur if not the first time we run) \n";
            }

            $last_epoch_filter = $last_known_epochtime;

        }
        else {

            if ($DEBUG) {
                print
"DEBUG: Using per section last epoch time for event filtering (no gaps in data should occur) \n";
            }

            $last_epoch_filter = $last_epoch_persection;

        }

    }

    @rawdata = grep( /^$nmon_var,/, @nmon );

    if ( @rawdata < 1 ) { return (1); }
    else {

        @rawdataheader = grep( /^$nmon_var,([^T].+),/, @nmon );
        if ( @rawdataheader < 1 ) {
            $msg =
"WARN: hostname: $HOSTNAME :$key section data is not consistent: the data header could not be identified, dropping the section to prevent data inconsistency \n";
            print "$msg";
            print ID_REF "$msg";

        }

        else {

            unless ( open( INSERT, ">$BASEFILENAME" ) ) {
                die("ERROR: Can not open /$BASEFILENAME\n");
            }

        }

    }

    @rawdata = sort(@rawdata);

    $rawdata[0] =~ s/\%/_PCT/g;
    $rawdata[0] =~ s/\(/_/g;
    $rawdata[0] =~ s/\)/_/g;
    $rawdata[0] =~ s/ /_/g;
    $rawdata[0] =~ s/__/_/g;
    $rawdata[0] =~ s/,_/,/g;

    @devices = split( /,/, $rawdata[0] );

    print INSERT (
qq|timestamp,type,serialnum,hostname,OStype,logical_cpus,interval,snapshots,ZZZZ,device,value|
    );

    # Count the number fields in header
    my $header =
"timestamp,type,serialnum,hostname,OStype,logical_cpus,interval,snapshots,ZZZZ,device,value";
    my @c                 = $header =~ /,/g;
    my $fieldsheadercount = @c;

    #print "\n COUNT IS $fieldsheadercount \n";

    $n = @rawdata;
    $n--;
    for ( $i = 1 ; $i < @rawdata ; $i++ ) {

        $TS = $UTC_START + $INTERVAL * ($i);
        $rawdata[$i] =~ s/,$//;
        @cols = split( /,/, $rawdata[$i] );

        $timestamp = $DATETIME{ $cols[1] };

     # Convert timestamp string to epoch time (from format: YYYY-MM-DD hh:mm:ss)
        my ( $year, $month, $day, $hour, $min, $sec ) = split /\W+/, $timestamp;
        my $ZZZZ_epochtime =
          timelocal( $sec, $min, $hour, $day, $month - 1, $year );

        # Write only new data if in realtime mode

        if ( $realtime eq "True" ) {

            if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                print INSERT (
qq|\n$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$logical_cpus,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[2],$cols[2]|
                );

                $count++;

            }

            else {

                if ($DEBUG) {
                    print "DEBUG, $key ignoring event $DATETIME{@cols[1]} \n";
                }

            }

        }

        elsif ( $colddata eq "True" || $fifo eq "True" ) {

            print INSERT (
qq|\n$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$logical_cpus,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[2],$cols[2]|
            );

            $count++;

        }

        for ( $j = 3 ; $j < @cols ; $j++ ) {

            $finaldata =
"$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$logical_cpus,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[$j],$cols[$j]";

# If the timestamp could not be found, there is a data anomaly and the section is not consistent
            if ( not $DATETIME{ $cols[1] } ) {

                $sanity_check                  = "1";
                $sanity_check_timestampfailure = "1";

            }

            # Count the number fields in data
            my @c              = $finaldata =~ /,/g;
            my $fieldsrawcount = @c;

            #print "\n COUNT IS $fieldsrawcount \n";

            if ( $fieldsrawcount != $fieldsheadercount ) {

                $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: $fieldsrawcount fields in data, $fieldsheadercount fields in header, extra fields detected (more fields in data than header), dropping this section to prevent data inconsistency \n";
                print "$msg";
                print ID_REF "$msg";

                $sanity_check = "1";

            }

            # If sanity check has not failed, write data
            if ( $sanity_check != "1" ) {

                $timestamp = $DATETIME{ $cols[1] };

     # Convert timestamp string to epoch time (from format: YYYY-MM-DD hh:mm:ss)
                my ( $year, $month, $day, $hour, $min, $sec ) = split /\W+/,
                  $timestamp;
                my $ZZZZ_epochtime =
                  timelocal( $sec, $min, $hour, $day, $month - 1, $year );

                # Write only new data if in realtime mode

                if ( $realtime eq "True" ) {

                    if ( $ZZZZ_epochtime > $last_epoch_filter ) {

                        print INSERT (
qq|\n$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$logical_cpus,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[$j],$cols[$j]|
                        );
                        $count++;
                    }

                }

                elsif ( $colddata eq "True" || $fifo eq "True" ) {

                    print INSERT (
qq|\n$ZZZZ_epochtime,$key,$SN,$HOSTNAME,$OStype,$logical_cpus,$INTERVAL,$SNAPSHOTS,$DATETIME{$cols[1]},$devices[$j],$cols[$j]|
                    );
                    $count++;
                }

            }

        }
        if ( $i < $n ) { print INSERT (""); }
    }
    print INSERT (qq||);

    # If sanity check has failed, remove data
    if ( $sanity_check != 0 && $sanity_check_timestampfailure != 0 ) {

        $msg =
"ERROR: hostname: $HOSTNAME :$key section is not consistent: Detected anomalies in events timestamp, dropping this section to prevent data inconsistency \n";
        print "$msg";
        print ID_REF "$msg";

        unlink $BASEFILENAME;
    }

    elsif ( $sanity_check != 0 ) {

        unlink $BASEFILENAME

    }

    else {
        if ( $count >= 1 ) {

            if (not $SILENT) {
                print "$key section: Wrote $count lines\n";
                print ID_REF "$key section: Wrote $count lines\n";
            }

            if ( $realtime eq "True" ) {

                if ($DEBUG) {
                    print
                      "Per section write, Last epochtime is $ZZZZ_epochtime \n";
                }

                # Open keyref for writing in create mode
                open( f, ">$keyref" );

                # save configuration extraction
                print f "last_epoch: $ZZZZ_epochtime \n";

            }

        }
        else {
            # Hey, only a header ! Don't keep empty files please
            unlink $BASEFILENAME;
        }
    }

}    # End Insert

########################################################
###	Get an nmon setting from csv file            ###
###	finds first occurance of $search             ###
###	Return the selected column...$return_col     ###
###	Syntax:                                      ###
###     get_setting($search,$col_to_return,$separator)##
########################################################

sub get_setting {

    my $i;
    my $value = "-1";
    my ( $search, $col, $separator ) = @_;    # search text, $col, $separator

    for ( $i = 0 ; $i < @nmon ; $i++ ) {

        if ( $nmon[$i] =~ /$search/ ) {
            $value = ( split( /$separator/, $nmon[$i] ) )[$col];
            $value =~ s/["']*//g;             #remove non alphanum characters
            return ($value);
        }    # end if

    }    # end for

    return ($value);

}    # end get_setting

#####################
##  Clean up       ##
#####################

sub clean_up_line {

    # remove characters not compatible with nmon variable
    # Max rrdtool variable length is 19 chars
    # Variable can not contain special characters (% - () )
    my ($x) = @_;

    # print ("clean_up, before: $i\t$nmon[$i]\n");
    $x =~ s/\%/Pct/g;

    # $x =~ s/\W*//g;
    $x =~ s/\/s/ps/g;    # /s  - ps
    $x =~ s/\//s/g;      # / - s
    $x =~ s/\(/_/g;
    $x =~ s/\)/_/g;
    $x =~ s/ /_/g;
    $x =~ s/-/_/g;
    $x =~ s/_KBps//g;
    $x =~ s/_tps//g;
    $x =~ s/[:,]*\s*$//;
    $retval = $x;

}    # end clean up

##########################################
##  Extract headings from nmon csv file ##
##########################################
sub initialize {

    %MONTH2NUMBER = (
        "jan", 1, "feb", 2, "mar", 3, "apr", 4,  "may", 5,  "jun", 6,
        "jul", 7, "aug", 8, "sep", 9, "oct", 10, "nov", 11, "dec", 12
    );

    @MONTH2ALPHA = (
        "junk", "jan", "feb", "mar", "apr", "may", "jun", "jul",
        "aug",  "sep", "oct", "nov", "dec"
    );

}    # end initialize

# Get data from nmon file, extract specific data fields (hostname, date, ...)
sub get_nmon_data {

    my $key;
    my $x;
    my $category;
    my %toc;
    my @cols;

    # Read nmon file
    unless ( open( FILE, $FILENAME ) ) { return (1); }
    @nmon = <FILE>;    # input entire file
    close(FILE);
    chomp(@nmon);

    # Cleanup nmon data remove trainig commas and colons
    for ( $i = 0 ; $i < @nmon ; $i++ ) {
        $nmon[$i] =~ s/[:,]*\s*$//;
    }

    # Get nmon/server settings (search string, return column, delimiter)
    $AIXVER   = &get_setting( "AIX",      2, "," );
    $DATE     = &get_setting( "date",     2, "," );

    # Allow hostname os
    if ($USE_FQDN) {
        chomp( $HOSTNAME = `hostname -f` );
    }
    else {
        $HOSTNAME = &get_setting( "host", 2, "," );
    }

    $INTERVAL = &get_setting( "interval", 2, "," );    # nmon sampling interval

    $MEMORY  = &get_setting( qq|lsconf,"Good Memory Size:|, 1, ":" );
    $MODEL   = &get_setting( "modelname",                   3, '\s+' );
    $NMONVER = &get_setting( "version",                     2, "," );

    $SNAPSHOTS = &get_setting( "snapshots", 2, "," );    # number of readings

    $STARTTIME = &get_setting( "AAA,time", 2, "," );
    ( $HR, $MIN ) = split( /\:/, $STARTTIME );

    # for AIX
    if ( $AIXVER ne "-1" ) {
        $SN = &get_setting( "systemid", 4, "," );
        $SN = ( split( /\s+/, $SN ) )[0];                # "systemid IBM,SN ..."
    }

    # for Power Linux
    else {
        $SN = &get_setting( "serial_number", 4, "," );
        $SN = ( split( /\s+/, $SN ) )[0];    # "serial_number=IBM,SN ..."
    }

    # undeterminated
    if ( $SN eq "-1" ) {
        $SN = $HOSTNAME;
    }
    elsif ( $SN eq "" ) {
        $SN = $HOSTNAME;
    }

    $TYPE = &get_setting( "^BBBP.*Type", 3, "," );
    if   ( $TYPE =~ /Shared/ ) { $TYPE = "SPLPAR"; }
    else                       { $TYPE = "Dedicated"; }

    $MODE = &get_setting( "^BBBP.*Mode", 3, "," );
    $MODE = ( split( /: /, $MODE ) )[1];

    # $MODE		=~s/\"//g;

    # Calculate UTC time (seconds since 1970)
    # NMON V9  dd/mm/yy
    # NMON V10+ dd-MMM-yyyy

    if ( $DATE =~ /[a-zA-Z]/ ) {    # Alpha = assume dd-MMM-yyyy date format
        ( $DAY, $MMM, $YR ) = split( /\-/, $DATE );
        $MMM = lc($MMM);
        $MON = $MONTH2NUMBER{$MMM};
    }
    else {
        ( $DAY, $MON, $YR ) = split( /\//, $DATE );
        $YR  = $YR + 2000;
        $MMM = $MONTH2ALPHA[$MON];
    }    # end if

## Calculate UTC time (seconds since 1970).  Required format for the rrdtool.

##  timelocal format
##    day=1-31
##    month=0-11
##    year = x -1900  (time since 1900) (seems to work with either 2006 or 106)

    $m = $MON - 1;    # jan=0, feb=2, ...

    $UTC_START = timelocal( 0, $MIN, $HR, $DAY, $m, $YR );
    $UTC_END = $UTC_START + $INTERVAL * $SNAPSHOTS;

    @ZZZZ = grep( /^ZZZZ,/, @nmon );
    for ( $i = 0 ; $i < @ZZZZ ; $i++ ) {

        @cols = split( /,/, $ZZZZ[$i] );
        ( $DAY, $MON, $YR ) = split( /-/, $cols[3] );
        $MON                  = lc($MON);
        $MON                  = "00" . $MONTH2NUMBER{$MON};
        $MON                  = substr( $MON, -2, 2 );
        $ZZZZ[$i]             = "$YR-$MON-$DAY $cols[2]";
        $DATETIME{ $cols[1] } = "$YR-$MON-$DAY $cols[2]";

    }    # end ZZZZ

    return (0);
}    # end get_nmon_data
