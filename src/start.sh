#!/usr/bin/env bash

set -e

service cron start
service nullmailer start
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=911396
service vsftpd start || true

exec apache2-foreground
