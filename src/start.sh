#!/usr/bin/env bash

set -e

# See Dockerfile for rationale why it's not a symlink.
rm -rf /etc/nullmailer
cp -r /var/www/.htsecure/nullmailer /etc &&
	chown -R mail:mail /etc/nullmailer &&
	chmod -R u=rX,g=rX,o= /etc/nullmailer

service cron start
service nullmailer start
service syslog-ng start
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=911396
service vsftpd start || true

exec apache2-foreground
