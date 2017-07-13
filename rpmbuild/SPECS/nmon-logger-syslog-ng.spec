Name: nmon-logger-syslog-ng
Version: 2.0.4
Release: 0
Summary: nmon-logger for syslog-ng
Source: %{name}.tar.gz
License: Apache 2.0

BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-build
Group:          System/Base
Vendor:         Guilhem Marchand

# Manage dependencies
Requires(pre): /usr/sbin/useradd, /usr/bin/getent, syslog-ng
Requires(postun): /usr/sbin/userdel

%description
This package provides Nmon performance monitoring logging for your Linux systems, and use syslog-ng to transfer data to your syslog-ng central servers.
For more information, please see: https://github.com/guilhemmarchand/nmon-logger

%prep
%setup -n %{name}

%pre
/usr/bin/getent group nmon || /usr/sbin/groupadd -r nmon
/usr/bin/getent passwd nmon || /usr/sbin/useradd -g nmon -r -d /etc/nmon-logger -s /sbin/nologin nmon

%build
# Nothing to build

%install
# create directories where the files will be located
mkdir -p $RPM_BUILD_ROOT/etc/cron.d
mkdir -p $RPM_BUILD_ROOT/etc/logrotate.d
mkdir -p $RPM_BUILD_ROOT/etc/nmon-logger
mkdir -p $RPM_BUILD_ROOT/etc/nmon-logger/default
mkdir -p $RPM_BUILD_ROOT/etc/nmon-logger/bin
mkdir -p $RPM_BUILD_ROOT/etc/nmon-logger/bin/nmon_external_cmd
mkdir -p $RPM_BUILD_ROOT/etc/syslog-ng
mkdir -p $RPM_BUILD_ROOT/etc/syslog-ng/conf.d
mkdir -p $RPM_BUILD_ROOT/var/log/nmon-logger

# put the files in to the relevant directories.
install -m 700 etc/cron.d/nmon-logger $RPM_BUILD_ROOT/etc/cron.d/
install -m 700 etc/logrotate.d/nmon-logger $RPM_BUILD_ROOT/etc/logrotate.d/
install -m 700 etc/nmon-logger/default/nmon.conf $RPM_BUILD_ROOT/etc/nmon-logger/default/
install -m 700 etc/nmon-logger/default/app.conf $RPM_BUILD_ROOT/etc/nmon-logger/default/
install -m 700 etc/nmon-logger/default/nmonparser_config.json $RPM_BUILD_ROOT/etc/nmon-logger/default/
install -m 700 etc/syslog-ng/conf.d/nmon-logger.conf $RPM_BUILD_ROOT/etc/syslog-ng/conf.d/
install -m 700 etc/nmon-logger/bin/linux.tgz $RPM_BUILD_ROOT/etc/nmon-logger/bin/
install -m 700 etc/nmon-logger/bin/nmon2* $RPM_BUILD_ROOT/etc/nmon-logger/bin/
install -m 700 etc/nmon-logger/bin/nmon_cleaner* $RPM_BUILD_ROOT/etc/nmon-logger/bin/
install -m 700 etc/nmon-logger/bin/nmon_helper.sh $RPM_BUILD_ROOT/etc/nmon-logger/bin/
install -m 700 etc/nmon-logger/bin/fifo_* $RPM_BUILD_ROOT/etc/nmon-logger/bin/
install -m 700 etc/nmon-logger/bin/nmon_external_cmd/*.sh $RPM_BUILD_ROOT/etc/nmon-logger/bin/nmon_external_cmd/
%post
echo
echo Restarting syslog-ng service:
service syslog-ng restart
echo
echo Nmon logger has been successfully installed. Within next minutes, the performance and configuration data collection will start automatically.
echo Please check the content of "/var/log/nmon-logger/"
echo You will also find a new process running under nmon account, you can get the current list of running processes for the nmon account: "ps -fu nmon"
echo

%postun
if [ "$1" = "0" ]; then
echo
if [ `ps -fu nmon | grep -v 'PID' | wc -l` -ne 0 ]; then echo "Killing running nmon processes:"; echo "**** list of running processes: ****"; echo `ps -fu nmon | grep '/var/log/nmon-logger/bin'`; ps -fu nmon | grep '/var/log/nmon-logger/bin' | awk '{print $2}' | xargs kill; sleep 5; fi
echo "Removing /etc/nmon-logger remaining files."; rm -rf /etc/nmon-logger
echo "Removing /var/log/nmon-logger remaining files."; rm -rf /var/log/nmon-logger
echo "Removing nmon user account"; userdel nmon
echo Restarting syslog-ng service:
service syslog-ng restart
echo
echo Nmon logger has been successfully uninstalled.
echo
fi

%clean
rm -rf $RPM_BUILD_ROOT
rm -rf %{_tmppath}/%{name}
rm -rf %{_topdir}/BUILD/%{name}

# list files owned by the package here
%files
%defattr(0644,root,root)
/etc/cron.d/nmon-logger
/etc/logrotate.d/nmon-logger
%attr(0755, nmon, nmon) /etc/nmon-logger
/etc/syslog-ng/conf.d/nmon-logger.conf
%attr(0755, nmon, nmon) /var/log/nmon-logger
