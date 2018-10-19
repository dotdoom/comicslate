#!/usr/bin/env bash

set -e

# Update IP ranges allowed to have access to Apache2 web server.
curl -sSL https://www.cloudflare.com/ips-v{4,6} | \
	sed 's/^/  Require ip /' > /etc/apache2/conf-available/cloudflare_ip.part
host pool.sysmon.hetzner.com | awk '{print "  Require ip", $NF}' | \
	sort > /etc/apache2/conf-available/hetzner_ip.part

service cron start
service nullmailer start

# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=911396
service vsftpd start || true

exec apache2-foreground
