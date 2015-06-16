#!/bin/bash

# install epel
sudo rpm --import http://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-6
wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
sudo yum localinstall -y epel-release-6-8.noarch.rpm

# install sshpass(noninteractive ssh password provider)
sudo yum install -y sshpass

# generate rsa key
mkdir -p ~/.ssh
if [[ ! -f ~/.ssh/id_rsa ]]; then
  ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -P ""
fi

# copy rsa key
cat ~/.ssh/id_rsa.pub | sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@192.168.33.11 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# install ansible
sudo yum install -y ansible

# configure host for ansible
cat <<EOF > hosts
[provision_dest]
192.168.33.11
EOF

# configure MySQL for ansible
cat <<EOF > my.cnf.j2
[client]
user = root
password = {{mysql_root_password}}
EOF

# create ansible playbook
cat <<EOF > playbook.yml
---
- hosts: provision_dest
  sudo: yes
  vars: 
    mysql_root_password: mysqlpass
    mysql_db_name: redmine
    mysql_db_user: redmine
    mysql_db_password: enimder
  tasks:
    - name: install Development Tools
      yum:
        name: "{{ item }}"
        state: present
      with_items:
        - "@Development Tools"
    
    - name: download yaml libraries
      get_url:
        url: "http://dl.fedoraproject.org/pub/epel/5/x86_64/{{ item }}"
        dest: "/home/vagrant/{{ item }}"
      with_items:
        - libyaml-0.1.2-8.el5.x86_64.rpm
        - libyaml-devel-0.1.2-8.el5.x86_64.rpm

    - name: install yaml libraries
      yum:
        name: "/home/vagrant/{{ item }}"
        disable_gpg_check: yes
        state: present
      with_items:
        - libyaml-0.1.2-8.el5.x86_64.rpm
        - libyaml-devel-0.1.2-8.el5.x86_64.rpm

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

    - name: copy my.cnf
      template: 
        src: my.cnf.j2
        dest: /root/.my.cnf
        owner: root
        mode: 0600
    
    - name: create database
      mysql_db:
        name: "{{ mysql_db_name }}"
        encoding: utf8
        state: present
    
    - name: grant database
      mysql_user:
        name: "{{ mysql_db_user }}"
        password: "{{ mysql_db_password }}"
        priv: "{{ mysql_db_name }}.*:ALL"
        host: localhost
        state: present
EOF

# run ansible playbook
ansible-playbook playbook.yml -i hosts
