#!/bin/sh

# go to
cd /opt/freeware/src/packages/SOURCES

# clean
rm -rf testing testing.zip* nmon-logger*

# Get the remote zip copy
wget https://github.com/guilhemmarchand/nmon-logger/archive/testing.zip

# Unzip
unzip testing.zip
rm testing.zip

# mv directory
mv nmon-logger-testing/nmon-logger-splunk-hec .

# Copy spec file
cp nmon-logger-testing/rpmbuild/SPECS_AIX/nmon-logger-splunk-hec.spec SPECS/

# clean
rm -rf nmon-logger-testing

# Create tar.gz archive
for i in nmon-logger-splunk-hec; do
    tar -cf $i.tar $i
    gzip $i.tar
done

# Build rpms
for i in nmon-logger-splunk-hec; do
    rpmbuild -ba /opt/freeware/src/packages/SPECS/$i
done

exit 0
