#!/bin/sh

# set -x

# Program name: fifo_reader.sh
# Purpose - read nmon data from fifo file and output to stdout
# Author - Guilhem Marchand
# Disclaimer:  this provided "as is".
# Date - June 2014

# Version 1.0.0
# 2017/04/03, Guilhem Marchand: remove -r option for better compatibility with old systems

# For AIX / Linux / Solaris

#################################################
## 	Your Customizations Go Here            ##
#################################################

# fifo to be read (valid choices are: fifo1 | fifo2
FIFO=$1

####################################################################
#############		Main Program 			############
####################################################################

while IFS= read line
do
    echo $line
done <$FIFO

exit 0
