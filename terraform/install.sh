#!/bin/bash
udo yum update -y
sudo amazon-linux-extras install -y php7.2
sudo yum install -y httpd php-mysqlnd
sudo systemctl start httpd
sudo systemctl enable httpd
mkdir -p /var/www/html
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride all/' /etc/httpd/conf/httpd.conf
