#!/usr/bin/env bash

set -e

# Update IP ranges allowed to have access to Apache2 web server.
curl -sSL https://www.cloudflare.com/ips-v{4,6} | \
	sed 's/^/  Require ip /' > /etc/apache2/conf-available/cloudflare_ip.part
host pool.sysmon.hetzner.com | awk '{print "  Require ip", $NF}' | \
	sort > /etc/apache2/conf-available/hetzner_ip.part

if [ ! -d /etc/letsencrypt/live ]; then
	# Obtain certificates for the first start.
	# TODO(dotdoom): this won't work with CF because it demands HTTPS.
	apachectl -D NoSSL -k start
	update-certificates.sh
	apachectl -k stop
fi

service cron start
service nullmailer start

# TODO(dotdoom): vsftpd starts, but this command fails. Find out why.
service vsftpd start || true

exec apache2-foreground
