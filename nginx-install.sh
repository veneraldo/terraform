#!/bin/bash
amazon-linux-extras install nginx1 -y
#yum -y install nginx
echo "Test from auto-scaling group nginx" > /usr/share/nginx/html/index.html
service nginx start
#git clone project.git
#cd project/html/
#cp -avr work /var/www/html/
