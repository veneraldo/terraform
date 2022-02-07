#!/bin/bash
yum -y install nginx git
echo "Hello, from auto-scaling group nginx server" > /var/www/html/index.html
service nginx start
#git clone project.git
#cd project/html/
#cp -avr work /var/www/html/
