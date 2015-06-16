#!/bin/bash

# generate rsa key
mkdir -p ~/.ssh
if [[ ! -f ~/.ssh/id_rsa ]]; then
  ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -P ""
fi

# install epel
sudo rpm --import http://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-6
wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
sudo yum localinstall -y epel-release-6-8.noarch.rpm

# install sshpass(noninteractive ssh password provider)
sudo yum install -y sshpass

# copy rsa key
cat ~/.ssh/id_rsa.pub | sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@192.168.33.11 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# install ansible
sudo yum install -y ansible

# configure ansible
cat <<EOF > hosts
[provision_dest]
192.168.33.11
EOF

cat <<EOF > playbook.yml
- hosts: provision_dest
  sudo: yes
  vars: 
    mysql_root_password: mysqlpass
    mysql_db_password : redmine
  tasks:
    - name: install MySQL
      yum:
        name: "{{ item }}"
        state: present
      with_items:
        - mysql-server
        - mysql-devel
        - MySQL-python
    
    - name: start MySQL
      service:
        name: mysqld
        state: started
        enabled: yes
    
    - name: set root password
      mysql_user:
        name: root
        host: localhost
        password: "{{ mysql_root_password }}"
    
    - name: create database
      mysql_db:
        name: redmine
        state: present
    
    - name: grant database
      mysql_user:
        name: redmine
        password: "{{ mysql_db_password }}"
        priv: "redmine.*:ALL"
        host: localhost
        state: present
EOF

# run ansible playbook
ansible-playbook playbook.yml -i hosts