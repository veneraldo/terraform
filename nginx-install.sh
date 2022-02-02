#!/bin/bash
yum -y install nginx git
service nginx start
git clone project.git
cd project/html/
cp -avr work /var/www/html/