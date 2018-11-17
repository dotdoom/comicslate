FROM php:apache

ARG HOSTNAME=comicslate.org

RUN echo \
	'APT::Get::Assume-Yes "true";' \
	'APT::Install-Suggests "0";' \
	'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/90forceyes.conf
RUN apt update

# Install syslog for tools like cron and vsftpd.
RUN apt install syslog-ng
COPY src/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

# Configure FTP server for admin access.
RUN apt install vsftpd
COPY src/vsftpd.conf /etc/vsftpd.conf
# Fix for https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=911396
RUN sed -n '54 { /if ! ps/q }; $q1' /etc/init.d/vsftpd && \
	sed -i '54s/if ! ps/if ps/' /etc/init.d/vsftpd
# Allow root login via FTP.
RUN sed -i /root/d /etc/ftpusers
RUN echo pasv_min_port=10100\\npasv_max_port=10200 >> /etc/vsftpd.conf
EXPOSE 21
EXPOSE 10100-10200

# Install gsutil.
RUN apt install gnupg2 software-properties-common
RUN echo "deb http://packages.cloud.google.com/apt \
	cloud-sdk-$(lsb_release -c -s) main" \
	> /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
RUN apt update && apt install google-cloud-sdk

# Automatically fetch certificates for our hostnames.
RUN apt install python-certbot-apache
RUN rm -rf /etc/letsencrypt && \
	ln -sf /var/www/.htsecure/certificates /etc/letsencrypt

# Daily cron jobs (e.g. rotate logs, create backups, update certificates etc).
RUN apt install cron logrotate p7zip git build-essential
RUN git clone --depth=1 https://github.com/hoytech/vmtouch.git && \
	cd vmtouch && make && make install && \
	cd .. && rm -rf vmtouch
COPY src/vmtouch.service /etc/init.d/vmtouch
RUN echo '0 3 * * * root /usr/local/bin/serverctl cron' >> /etc/crontab
COPY src/logrotate "/etc/logrotate.d/${HOSTNAME}"

# nullmailer asks questions, ignore them because we configure it later.
RUN DEBIAN_FRONTEND=noninteractive apt install nullmailer
RUN echo "${HOSTNAME}" > /etc/mailname
# In nullmailer Debian 1:1.13-1.2, 'mailname' is referenced as '../mailname'
# relative to /etc/nullmailer. Symplinking /etc/nullmailer to e.g.
# /var/www/.htsecure/nullmailer makes 'mailname' resolve to
# /var/www/.htsecure/mailname, which is wrong. So we copy over in start.sh.
# See https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=504184 (patch 12).

# Configure Apache web server.
RUN a2enmod ssl rewrite headers macro ext_filter
RUN mv "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini"
COPY src/apache2.conf "/etc/apache2/sites-enabled/${HOSTNAME}.conf"
COPY src/php.ini "${PHP_INI_DIR}/conf.d/30-${HOSTNAME}.ini"
# In addition to port 80 (http) from the base image, export 443 (https).
EXPOSE 443

# PHP extensions.
RUN apt install libpng-dev libfreetype6-dev libjpeg62-turbo-dev && \
	docker-php-ext-configure gd \
		--with-freetype-dir=/usr/include/ \
		--with-jpeg-dir=/usr/include/ && \
	docker-php-ext-install -j$(nproc) gd

# Do "grep -c" so that grep reads the whole input and curl is happy.
# In addition, normalize the exit code (return strictly 0 or 1).
HEALTHCHECK CMD curl -sSL --connect-to localhost \
	"https://${HOSTNAME}/" | grep -c freefall || false

COPY src/serverctl /usr/local/bin/serverctl

# Confirm that the config file we got is valid.
# /var/www will be mounted externally, create directory for config test only.
RUN mkdir -p /var/www/.htsecure/log && \
	/usr/local/bin/serverctl update_whitelisted_ips && \
	apachectl -D NoSSL -t && \
	rm -rf /var/www/.htsecure

ENTRYPOINT []
CMD ["serverctl", "start"]
