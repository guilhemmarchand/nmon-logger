#!/bin/sh

export VAGRANT_HOME=`pwd`

echo "****************** Destroying vagrant VMs: ******************"

for server in `grep -v -e ^# -e localhost -e ^$ hosts | awk '{print $2}'`; do
   vagrant destroy $server -f
done

# clean vagrant various files
data="
gems
tmp
setup_version
rgloader
data
insecure_private_key
.vagrant"

for data in $data; do
   rm -rf $data
done

echo "****************** Done. ******************"
