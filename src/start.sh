#!/usr/bin/env bash

set -e

# Have to provide configuration here to substitute $$ and let syslog-ng write
# logs to "docker logs" output.
cat >/etc/syslog-ng/syslog-ng.conf <<SYSLOG
@version: 3.8
source s_src {
	unix-stream("/dev/log");
	internal();
};
destination d_stderr { pipe("/proc/$$/fd/2"); };
log { source(s_src); destination(d_stderr); };
SYSLOG

service cron start
service nullmailer start
service syslog-ng start
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=911396
service vsftpd start || true

exec apache2-foreground
