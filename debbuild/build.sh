#!/usr/bin/env bash

# Install git
sudo apt-get install -y git

# Clone rep
git clone https://github.com/guilhemmarchand/nmon-logger.git

# Enter rep
cd ~/nmon-logger

# Checkout testing
git checkout testing; git pull

# Copy sources to build
rsync -av nmon-logger-rsyslog/* debbuild/nmon-logger-rsyslog/
rsync -av nmon-logger-syslog-ng/* debbuild/nmon-logger-syslog-ng/
rsync -av nmon-logger-splunk-hec/* debbuild/nmon-logger-splunk-hec/

# cleaning
rm debbuild/nmon-logger*/README

# Enter build
cd ~/nmon-logger/debbuild

# Build nmon-logger-syslog-ng
dpkg-deb --build nmon-logger-syslog-ng

# Rename deb with version number
for deb in `ls nmon-logger-syslog-ng.deb`; do name=`echo $deb | awk -F. '{print $1}'`; version=`cat ${name}/DEBIAN/control | grep Version | awk '{print $2}'`; mv $deb ${name}-${version}.deb; done

# Return rep
cd ~/nmon-logger

rm debbuild/nmon-logger-rsyslog/etc/rsyslog.d/*
cp nmon-logger-rsyslog/etc/rsyslog.d/20-nmon-logger.conf_ubuntu debbuild/nmon-logger-rsyslog/etc/rsyslog.d/20-nmon-logger.conf

# Enter build
cd ~/nmon-logger/debbuild

# Build nmon-logger-rsyslog
dpkg-deb --build nmon-logger-rsyslog

# Rename deb with version number and OS name
for deb in `ls nmon-logger-rsyslog.deb`; do name=`echo $deb | awk -F. '{print $1}'`; version=`cat ${name}/DEBIAN/control | grep Version | awk '{print $2}'`; mv $deb ${name}-ubuntu-${version}.deb; done

# Return rep
cd ~/nmon-logger

rm debbuild/nmon-logger-rsyslog/etc/rsyslog.d/*
cp nmon-logger-rsyslog/etc/rsyslog.d/20-nmon-logger.conf_debian debbuild/nmon-logger-rsyslog/etc/rsyslog.d/20-nmon-logger.conf

# Enter build
cd ~/nmon-logger/debbuild

# Build nmon-logger-rsyslog
dpkg-deb --build nmon-logger-rsyslog

# Rename deb with version number and OS name
for deb in `ls nmon-logger-rsyslog.deb`; do name=`echo $deb | awk -F. '{print $1}'`; version=`cat ${name}/DEBIAN/control | grep Version | awk '{print $2}'`; mv $deb ${name}-debian-${version}.deb; done

# Return rep
cd ~/nmon-logger

# Enter build
cd ~/nmon-logger/debbuild

# Build nmon-logger-splunk-hec
dpkg-deb --build nmon-logger-splunk-hec

# Rename deb with version number and OS name
for deb in `ls nmon-logger-splunk-hec.deb`; do name=`echo $deb | awk -F. '{print $1}'`; version=`cat ${name}/DEBIAN/control | grep Version | awk '{print $2}'`; mv $deb ${name}-${version}.deb; done

exit 0