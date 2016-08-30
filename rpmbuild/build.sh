#!/usr/bin/env bash

# Install git
sudo yum install -y rpm-build rpmdevtools git

# Clone rep
git clone https://github.com/guilhemmarchand/nmon-logger.git

# Enter rep
cd nmon-logger

# Checkout testing
git checkout testing; git pull

# Go back home
cd

# Create rpm tree
rpmdev-setuptree

# Copy sources
cp -a nmon-logger/nmon-logger-rsyslog rpmbuild/SOURCES/
cp -a nmon-logger/nmon-logger-syslog-ng rpmbuild/SOURCES/

# Create tar archives
cd rpmbuild/SOURCES/
for i in `ls -d * | grep -v tar.gz`; do
tar -cvzf $i.tar.gz $i
done

# Go back home
cd

# Copy specs
cp nmon-logger/rpmbuild/SPECS/*.spec rpmbuild/SPECS/

# Enter build
cd rpmbuild

# Build rpms
for i in `ls SPECS/*.spec`; do
rpmbuild -ba $i
done

exit 0