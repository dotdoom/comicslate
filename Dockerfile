FROM php:7.4-apache

ARG HOSTNAME=comicslate.org

RUN echo \
	'APT::Get::Assume-Yes "true";' \
	'APT::Install-Suggests "0";' \
	'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/90forceyes.conf
RUN apt-get update

# Install dumb-init to properly handle and proxy signals.
RUN apt-get install dumb-init

# Install syslog for tools like cron and vsftpd.
RUN apt-get install syslog-ng
COPY src/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

# Configure FTP server for admin access.
RUN apt-get install vsftpd
COPY src/vsftpd.conf /etc/vsftpd.conf
# Allow root login via FTP.
RUN echo pasv_min_port=10100\\npasv_max_port=20100 >> /etc/vsftpd.conf
EXPOSE 21
EXPOSE 10100-20100

# Automatically fetch certificates for our hostnames.
RUN apt-get install python3-certbot-apache
RUN rm -rf /etc/letsencrypt && \
	ln -sf /var/www/.htsecure/certificates /etc/letsencrypt

# Daily cron jobs (e.g. rotate logs, create backups, update certificates etc).
RUN apt-get install cron logrotate p7zip git build-essential
# Restrict loose permissions which logrotate doesn't like for security reasons.
# Base image change: https://github.com/docker-library/php/pull/745.
RUN . "${APACHE_ENVVARS}" && chmod 0750 "${APACHE_LOG_DIR?}"
RUN git clone --depth=1 https://github.com/hoytech/vmtouch.git && \
	cd vmtouch && make && make install && \
	cd .. && rm -rf vmtouch
COPY src/vmtouch.service /etc/init.d/vmtouch
RUN echo '0 3 * * * root /usr/local/bin/serverctl cron' >> /etc/crontab
COPY src/logrotate "/etc/logrotate.d/${HOSTNAME}"

# nullmailer asks questions, ignore them because we configure it later.
RUN DEBIAN_FRONTEND=noninteractive apt-get install nullmailer
RUN echo "${HOSTNAME}" > /etc/mailname
# In nullmailer Debian 1:1.13-1.2, 'mailname' is referenced as '../mailname'
# relative to /etc/nullmailer. Symplinking /etc/nullmailer to e.g.
# /var/www/.htsecure/nullmailer makes 'mailname' resolve to
# /var/www/.htsecure/mailname, which is wrong. So we copy over in start.sh.
# See https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=504184 (patch 12).

# NodeJS and Chrome for comicsbot.
# https://github.com/nodesource/distributions/blob/master/README.md
RUN apt-get install ca-certificates curl gnupg
# Keep in sync with src/comicsbot.service.
ENV NVM_DIR=/opt/nvm
RUN mkdir -p "${NVM_DIR?}" && chown www-data "${NVM_DIR?}"
USER www-data
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
USER root
# Install Google Chrome to pull in APT dependencies -- the binary itself will
# not be used.
RUN apt-get update && \
	apt-get install wget gnupg ca-certificates && \
	wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
	echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' >> /etc/apt/sources.list.d/google-chrome.list && \
	apt-get update && \
	apt-get install google-chrome-stable fonts-noto-color-emoji libxshmfence1
# Service file for comicsbot.
COPY src/comicsbot.service /etc/init.d/comicsbot
# Test that the bot can start; poor man's check for browser startup too.
RUN mkdir /var/www/.htsecure && \
	service comicsbot start && \
	pgrep -a '^chrome' && \
	service comicsbot stop && \
	rm -rf /var/www/.htsecure

# Configure Apache web server.
RUN a2enmod ssl rewrite headers macro ext_filter proxy_http
RUN mv "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini"
COPY src/apache2.conf "/etc/apache2/sites-enabled/${HOSTNAME}.conf"
COPY src/php.ini "${PHP_INI_DIR}/conf.d/30-${HOSTNAME}.ini"
# Default site configuration is useless, and regularly logs OPTIONS Apache2 wake
# requests to the container log, cluttering it up. Note that disabling default
# website means that requests without or with unknown "Host" header will go to
# the first declared VHost. This can lead to discovery of what website is
# running on a certain IP address.
RUN a2dissite 000-default
# In addition to port 80 (http) from the base image, export 443 (https).
EXPOSE 443

# PHP extensions.
RUN apt-get install libpng-dev libfreetype6-dev libjpeg62-turbo-dev && \
	docker-php-ext-configure gd --with-freetype --with-jpeg && \
	docker-php-ext-install -j$(nproc) gd

# Do "grep -c" so that grep reads the whole input and curl is happy.
# In addition, normalize the exit code (return strictly 0 or 1).
HEALTHCHECK CMD curl -sSL --connect-to localhost \
	"https://${HOSTNAME}/" | grep -c app.comicslate.org || false

COPY src/serverctl /usr/local/bin/serverctl

# Confirm that the config file we got is valid.
# /var/www will be mounted externally, create directory for config test only.
RUN mkdir -p /var/www/.htsecure/log && \
	/usr/local/bin/serverctl update_whitelisted_ips && \
	apachectl -D NoSSL -t && \
	rm -rf /var/www/.htsecure

# Save Git commit hash of this build into /docker_repo_version.
COPY .git /tmp/repo/.git
RUN git -C /tmp/repo log -1 > /docker_repo_version && rm -rf /tmp/repo

ENTRYPOINT []
CMD ["dumb-init", "--", "serverctl", "start"]
