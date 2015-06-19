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

# create config file for redmine
cat <<EOF > database.yml.j2
production:
  adapter: mysql2
  database: {{ mysql_db_name }}
  host: localhost
  username: {{ mysql_db_user }}
  password: {{ mysql_db_password }}
  encoding: utf8
EOF

# create config file for redmine
cat <<EOF > passenger.conf.j2
LoadModule passenger_module /usr/local/lib/ruby/gems/1.9.1/gems/passenger-5.0.10/buildout/apache2/mod_passenger.so
<IfModule mod_passenger.c>
  PassengerRoot /usr/local/lib/ruby/gems/1.9.1/gems/passenger-5.0.10
  PassengerDefaultRuby /usr/local/bin/ruby
</IfModule>
EOF

# create config file for redmine
cat <<EOF > redmine.conf.j2
<VirtualHost *:80>
   #ServerName www.yourhost.com
   # !!! Be sure to point DocumentRoot to 'public'!
   #DocumentRoot /somewhere/public
   DocumentRoot /usr/local/redmine/public
   #<Directory /somewhere/public>
   <Directory /usr/local/redmine/public>
      # This relaxes Apache security settings.
      AllowOverride all
      # MultiViews must be turned off.
      Options -MultiViews
      # Uncomment this if you're on Apache >= 2.4:
      #Require all granted
   </Directory>
</VirtualHost>
EOF

# create ansible playbook
cat <<EOF > playbook.yml
---
- hosts: provision_dest
  sudo: yes
  vars: 
    src_dir: /usr/local/src
    mysql_root_password: mysqlpass
    mysql_db_name: redmine
    mysql_db_user: redmine
    mysql_db_password: enimder
    ruby_major_version: 1.9
    ruby_version: "ruby-{{ ruby_major_version }}.3-p551"
    redmine_version: redmine-2.6.5
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

    - name: install ruby relational packages
      yum:
        name: "{{ item }}"
        state: present
      with_items:
        - apr-devel
        - apr-util-devel
        - curl-devel
        - httpd
        - httpd-devel
        - openssl-devel
        - readline-devel
        - zlib-devel
    
    - name: install mysql relational packages
      yum:
        name: "{{ item }}"
        state: present
      with_items:
        - mysql-server
        - mysql-devel
        - MySQL-python
    
    - name: start mysql
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
        
    - name: download ruby
      get_url:
        url: "http://cache.ruby-lang.org/pub/ruby/{{ ruby_major_version }}/{{ ruby_version }}.tar.gz"
        dest: "{{ src_dir }}"
        
    - name: expand ruby
      command: chdir="{{ src_dir }}" tar zxvf {{ ruby_version }}.tar.gz
      
    - name: configure ruby
      command: chdir="{{ src_dir }}/{{ ruby_version }}" ./configure
      
    - name: make ruby
      command: chdir="{{ src_dir }}/{{ ruby_version }}" make
      
    - name: install ruby
      command: chdir="{{ src_dir }}/{{ ruby_version }}" make install

    - name: install rails
      gem:
        name: rails
        version: 3.2
        # state: present # not required. present is default.
        executable: /usr/local/bin/gem
        user_install: no
        
    - name: install ruby's relation package
      gem:
        name: "{{ item }}"
        # state: present # not required. present is default.
        executable: /usr/local/bin/gem
        user_install: no
      with_items:
        #- rack # It'll be installed depend on the rails.
        #- i18n # It'll be installed depend on the rails.
        - mysql
        
    - name: download redmine
      get_url:
        url: "http://www.redmine.org/releases/{{ redmine_version }}.tar.gz"
        dest: "{{ src_dir }}"
        
    - name: expand redmine
      command: chdir=/usr/local tar zxvf {{ src_dir }}/{{ redmine_version }}.tar.gz
      
    - name: rename redmine
      command: chdir=/usr/local mv {{ redmine_version }} redmine
      
    - name: change owner redmine
      command: chdir=/usr/local chown -R root:root redmine
      
    #- name: copy database config file
    #  command: chdir=/usr/local/redmine/config cp database.yml.example database.yml
      
    - name: copy database.yml
      template: 
        src: database.yml.j2
        dest: /usr/local/redmine/config/database.yml
        mode: 0644

    - name: run bundler
      command: chdir=/usr/local/redmine bundle install --without development test postgresql sqlite rmagick
      environment:
        PATH: "{{ ansible_env.PATH }}:/usr/local/bin"
      
    - name: run rake
      command: chdir=/usr/local/redmine rake generate_secret_token
      environment:
        PATH: "{{ ansible_env.PATH }}:/usr/local/bin"
      
    - name: run rake
      command: chdir=/usr/local/redmine rake db:migrate RAILS_ENV=production
      environment:
        PATH: "{{ ansible_env.PATH }}:/usr/local/bin"
      
    - name: run rake
      command: chdir=/usr/local/redmine rake redmine:load_default_data RAILS_ENV=production REDMINE_LANG=ja
      environment:
        PATH: "{{ ansible_env.PATH }}:/usr/local/bin"
      
    - name: install passenger
      gem:
        name: passenger
        executable: /usr/local/bin/gem
        user_install: no
      
    - name: run passenger-install-apache2-module
      command: passenger-install-apache2-module --auto --languages=ruby
      environment:
        PATH: "{{ ansible_env.PATH }}:/usr/local/bin"
      
    - name: copy passenger.conf
      template: 
        src: passenger.conf.j2
        dest: /etc/httpd/conf.d/passenger.conf
        mode: 0644
      
    - name: copy redmine.conf
      template: 
        src: redmine.conf.j2
        dest: /etc/httpd/conf.d/redmine.conf
        mode: 0644
      
    - name: start httpd
      service:
        name: httpd
        state: started
        enabled: yes
EOF

# run ansible playbook
ansible-playbook playbook.yml -i hosts
