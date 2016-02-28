#!/bin/sh

# Don't check for known_host
export ANSIBLE_HOST_KEY_CHECKING=False
export VAGRANT_HOME=`pwd`

echo "****************** Starting vagrant VMs: ******************"
vagrant up

echo "****************** Verifying ping connection: ******************"

# Check ping connection
ansible all -m ping --private-key=insecure_private_key -u vagrant -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory

# run playbooks
echo "****************** Running: part1_deploysplunk.yml ******************"
ansible-playbook --private-key=insecure_private_key -u vagrant -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory deployment.yml

echo "****************** Done, hosts map: ******************"
cat hosts | grep -v localhost
echo "******************************************************"

exit 0
