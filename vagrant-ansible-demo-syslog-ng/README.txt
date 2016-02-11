
###################################
#### Notes about this package: ####
###################################

You can use this package to get a full working environment of an nmon-logger deployment using Vagrant ! Up in 5 minutes :-)

*** Requirements ***

You need to have:

- Vagrant --> https://www.vagrantup.com/downloads.html

If you want to use Virtualbox as the provider (which i will recommend as it is free, easy to use and install):

- VirtualBox --> https://www.virtualbox.org/wiki/Downloads

- git --> sudo apt-get install git / sudo yum install git

- Internet connexion: The host that runs Vagrant required an Internet access to download the Vagrant boxes, and run the Ansible playbook

- Splunk Universal Forwarder compressed archive for Linux 64-bits (tgz) --> http://www.splunk.com/en_us/download/universal-forwarder.html

- Splunk indexer or standalone Splunk instance that will receive data from virtual machines

*** What does this package ? ***

This package will create from scratch and totally automatically:

- 1 virtual machine acting as syslog-ng collector, and running Splunk Universal Forwarder

- 2 virtual machines running the nmon-looger and sending their data to central syslog-ng collectors

--> machine1 : syslog-ng collector running Splunk Universal Forwarder
--> machine2 : syslog-ng client running the nmon-logger
--> machine3 : syslog-ng client running the nmon-logger


#######################
#### INSTALLATION: ####
#######################

Very easy !

This an installation proposal, you are free to customize configurations and steps at your own risks :-)

1. Clone this git repository

$ mkdir /opt/deployment
$ git clone https://github.com/guilhemmarchand/nmon-logger.git

2. Download the Splunk Universal Forwarder tgz archive

Download from http://www.splunk.com/en_us/download/universal-forwarder.html the archive for Linux x86 64-bits in tgz format

$ mkdir /opt/deployment/splunk_bin

And copy the tgz archive here.

3. Ubuntu or CentOS ?

Decide if you want to run Ubuntu boxes, or CentOS boxes:

- Ubuntu --> Ubuntu boxes is the default choice, you have nothing to do
- CentOS --> Edit the VagrantFile, comment out the secondary "machine.vm.box" and comment the current line

4. Start the Vagrant magic !

$ cd /opt/deployment/nmon-logger/vagrant-ansible-demo-syslog-ng
$ vagrant up

And wait for Vagrant to start the virtual machines, and finally Ansible will run the playbook:

***************

==> machine1: Box 'ubuntu/vivid64' could not be found. Attempting to find and install...
    machine1: Box Provider: virtualbox
    machine1: Box Version: >= 0
==> machine1: Loading metadata for box 'ubuntu/vivid64'
    machine1: URL: https://atlas.hashicorp.com/ubuntu/vivid64
==> machine1: Adding box 'ubuntu/vivid64' (v20160203.0.0) for provider: virtualbox
    machine1: Downloading: https://atlas.hashicorp.com/ubuntu/boxes/vivid64/versions/20160203.0.0/providers/virtualbox.box
==> machine1: Box download is resuming from prior download progress
==> machine1: Successfully added box 'ubuntu/vivid64' (v20160203.0.0) for 'virtualbox'!
==> machine1: Importing base box 'ubuntu/vivid64'...
==> machine1: Matching MAC address for NAT networking...
==> machine1: Checking if box 'ubuntu/vivid64' is up to date...
==> machine1: Setting the name of the VM: vagrant-ansible-demo-syslog-ng_machine1_1455144754566_36922
==> machine1: Clearing any previously set forwarded ports...
==> machine1: Clearing any previously set network interfaces...
==> machine1: Preparing network interfaces based on configuration...
    machine1: Adapter 1: nat
    machine1: Adapter 2: hostonly
    machine1: Adapter 3: hostonly
==> machine1: Forwarding ports...
    machine1: 22 (guest) => 2222 (host) (adapter 1)
==> machine1: Running 'pre-boot' VM customizations...
==> machine1: Booting VM...
==> machine1: Waiting for machine to boot. This may take a few minutes...
    machine1: SSH address: 127.0.0.1:2222
    machine1: SSH username: vagrant
    machine1: SSH auth method: private key
    machine1: Warning: Remote connection disconnect. Retrying...
==> machine1: Machine booted and ready!
==> machine1: Checking for guest additions in VM...
    machine1: The guest additions on this VM do not match the installed version of
    machine1: VirtualBox! In most cases this is fine, but in rare cases it can
    machine1: prevent things such as shared folders from working properly. If you see
    machine1: shared folder errors, please make sure the guest additions within the
    machine1: virtual machine match the version of VirtualBox you have installed on
    machine1: your host and reload your VM.
    machine1:
    machine1: Guest Additions Version: 4.3.36
    machine1: VirtualBox Version: 5.0
==> machine1: Setting hostname...
==> machine1: Configuring and enabling network interfaces...
==> machine1: Mounting shared folders...
    machine1: /vagrant => /home/guilhem/Documents/git/nmon-logger/vagrant-ansible-demo-syslog-ng

..............

***************

Ok, there you go, you 4 machines ready and running.

5. Splunk configuration:

In your Splunk instance, download and install the Nmon Performance Monitor application: https://splunkbase.splunk.com/app/1753

Optionally, you can set the Splunk deployment server of your instance to automatically deploy the TA-nmon package to machine1 running the Splunk Universal Forwarder

$ cd /opt/splunk/etc/deploy-apps
$ tar -xvzf /opt/splunk/etc/apps/nmon/resources/TA-nmon*.tar.gz

And configure the deployment server to deploy to machine1

For more details, see: http://nmonsplunk.wikidot.com/documentation:installation:bydeployment:distributed "4. Configuring the deployment server to push the TA-nmon to Universal Forwarders"

Et voilà !














