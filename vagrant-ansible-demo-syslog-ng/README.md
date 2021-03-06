
# Instant virtual environment with Vagrant / Ansible

You can use this package to get a full working environment of an nmon-logger deployment using Vagrant ! Up in 5 minutes :-)

## Requirements:

* Vagrant --> https://www.vagrantup.com/downloads.html

If you want to use Virtualbox as the provider (which i will recommend as it is free, easy to use and install):

* VirtualBox --> https://www.virtualbox.org/wiki/Downloads

* git --> sudo apt-get install git / sudo yum install git

* Internet connexion: The host that runs Vagrant required an Internet access to download the Vagrant boxes, and run the Ansible playbook

* Splunk Universal Forwarder compressed archive for Linux 64-bits (tgz) --> http://www.splunk.com/en_us/download/universal-forwarder.html

* Splunk compressed archive for Linux 64-bits (tgz) --> http://www.splunk.com/en_us/download/splunk-enterprise.html

**What does this package will do ?**

This package will create from scratch and totally automatically:

* 1 Splunk instance fully configured, with the Nmon Performance monitor application up & running

* 2 virtual machines acting as active / active Rsyslog collectors, and running Splunk Universal Forwarder

* 2 virtual machines running the nmon-looger and sending their data to central rsyslog collectors

* Host summary:

    * 192.168.33.100  splunk
    * 192.168.33.101  syslog-ng-server1
    * 192.168.33.102  syslog-ng-client1
    * 192.168.33.103  syslog-ng-client2

## Start the virtual env

Very easy !

*This an installation proposal, you are free to customize configurations and steps at your own risks :-)*

### Clone this git repository

`$ mkdir /opt/deployment`

`$ git clone https://github.com/guilhemmarchand/nmon-logger.git`

### Download Splunk and Splunk Universal Forwarder tgz archives

--> Choose Linux 64 bits in tgz format (tar.gz)

`$ mkdir /opt/deployment/splunk_bin`

And copy the tgz archives here.

### Ubuntu or CentOS ?

Decide if you want to run Ubuntu boxes, or CentOS boxes:

- Ubuntu --> Ubuntu boxes is the default choice, you have nothing to do
- Debian --> Edit the VagrantFile, comment out the secondary "machine.vm.box" and comment the current line
- CentOS --> Edit the VagrantFile, comment out the secondary "machine.vm.box" and comment the current line

### Start the Vagrant magic !

`$ cd /opt/deployment/nmon-logger/vagrant-ansible-demo-syslog-ng`

`$ ./run.sh`

And wait for Vagrant to start the virtual machines, and finally Ansible will be run and to automatically deploy and configure the virtual env.

Ok, there you go, you have 5 machines ready and running.

### Access Splunk:

Open your web browser and access to the virtual IP: https://192.168.33.100

* login: admin
* password: changeme

**See it in action:**

[![asciicast](https://asciinema.org/a/7hkiyw43cistxg7192zux3mvr.png)](https://asciinema.org/a/7hkiyw43cistxg7192zux3mvr?speed=15)


![screen1](./docs/screen001.png)

![screen2](./docs/screen002.png)
