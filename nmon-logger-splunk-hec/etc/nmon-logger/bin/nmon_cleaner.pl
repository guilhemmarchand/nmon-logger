#!/usr/bin/perl

# Program name: nmon_cleaner.pl
# Compatibility: Perl x
# Purpose - Clean nmon data upon retention expiration
# Author - Guilhem Marchand
# Date of first publication - Jan 2016

# Releases Notes:

# - Jan 2016, V1.0.0: Guilhem Marchand, Initial version

$version = "1.0.0";

use Time::Local;
use Time::HiRes;
use Getopt::Long;
use File::stat;    # use the object-oriented interface to stat

# LOGGING INFORMATION:
# - The program uses the standard logging Python module to display important messages in Splunk logs
# - Every message of the script will be indexed and accessible within Splunk splunkd logs

#################################################
##      Arguments Parser
#################################################

# Default values
my $NMON_HOME    = "";
my $MAXSECONDS_NMON        = "";
my $verbose;

$result = GetOptions(
    "nmon_home=s"    => \$NMON_HOME,       # string
    "maxseconds_nmon=s"   => \$MAXSECONDS_NMON,      # string
    "version"             => \$VERSION,              # flag
    "help"                => \$help                  # flag
);

# Show version
if ($VERSION) {
    print("nmon_cleaner.pl version $version \n");

    exit 0;
}

# Show help
if ($help) {

    print( "

Help for nmon_cleaner.pl:

Available options are:
	
--nmon_home <full path> :The Nmon home directory that contains directories to maintain (mandatory)
--maxseconds_nmon <value> :Set the maximum file retention in seconds for nmon files, every files older than this value will be permanently removed
--version :Show current program version \n
"
    );

    exit 0;
}

#################################################
##      Parameters
#################################################

# Default values for NMON retention is 600 seconds (10 min) since its last modification
my $MAXSECONDS_NMON_DEFAULT = 600;

#################################################
##      Functions
#################################################

#################################################
##      Program
#################################################

# Processing starting time
my $t_start = [Time::HiRes::gettimeofday];

# Local time
my $time = localtime;

# Verify NMON_HOME definition
if ( ! -d "$NMON_HOME" ) {
    print(
"\n$time INFO: The main var directory $NON_HOME has not been found, there is no need to run now. \n"
    );
    exit(0);
}

# var directories
my $APP_MAINVAR = "$NMON_HOME/var";

if ( !-d "$APP_MAINVAR" ) {
    print(
"\n$time INFO: main var directory not found ($APP_MAINVAR),  no need to run.\n"
    );
    exit 0;
}


####################################################################
#############		Main Program
####################################################################

# check retention
if ( not "$MAXSECONDS_NMON" ) {
    $MAXSECONDS_NMON = $MAXSECONDS_NMON_DEFAULT;
}

# Print starting message
print("$time INFO: Starting nmon cleaning\n");
print("$time INFO: Nmon home directory $NMON_HOME nmon_cleaner version: $version Perl version: $] \n");

# Set current epoch time
$epoc = time();

# Counter
$count = 0;

# NMON Items to clean
@cleaning = ("$APP_MAINVAR/nmon_repository/*.nmon");

# Enter loop
foreach $key (@cleaning) {

    @files = glob($key);

    foreach $file (@files) {
        if ( -f $file ) {

            # Get file timestamp
            my $file_timestamp = stat($file)->mtime;

            # Get difference
            my $timediff = $epoc - $file_timestamp;

            # If retention has expired
            if ( $timediff > $MAXSECONDS_NMON ) {

                # information
                print ("$time INFO: Max set retention of $MAXSECONDS_NMON seconds seconds expired for file: $file \n");

                # purge file
                unlink $file;

                # Increment counter
                $count++;

            }

        }

    }

    if ( $count eq 0 ) {
        print ("$time INFO: No files with expired retention found in directory: $key, no action required. \n");
    }
    else {
        print("$time INFO: $count files were permanently removed from $key \n");
    }

}

#############################################
#############  Main Program End 	############
#############################################

# Show elapsed time
my $t_end = [Time::HiRes::gettimeofday];
print "$time INFO: Elapsed time was: ",
  Time::HiRes::tv_interval( $t_start, $t_end ) . " seconds \n";

exit(0);