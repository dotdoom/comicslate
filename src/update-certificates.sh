#!/usr/bin/env bash

set -e

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

admin_email="$(cat /etc/nullmailer/adminaddr)"
cert_updated=""
for vhost_path in /var/www/*.*; do
	domain="$(basename "${vhost_path?}")"
	if certbot certonly \
		--agree-tos \
		--quiet \
		--email "${admin_email?}" \
		--renew-by-default \
		--domain "${domain?}" \
		--webroot \
		--webroot-path "/var/www/${domain?}"; then
		cert_updated=y
	fi
done

[ -n "$cert_updated" ]
