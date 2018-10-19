FROM php:apache

ARG HOSTNAME=comicslate.org

RUN echo \
	'APT::Get::Assume-Yes "true";' \
	'APT::Install-Suggests "0";' \
	'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/90forceyes.conf
RUN apt update
RUN apt dist-upgrade

# Configure FTP server for admin access.
RUN apt install vsftpd
COPY src/vsftpd.conf /etc/vsftpd.conf
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
COPY src/update-certificates.sh /usr/local/bin/update-certificates.sh
RUN rm -rf /etc/letsencrypt && \
	ln -sf /var/www/.htsecure/certificates /etc/letsencrypt

# Daily cron jobs (e.g. rotate logs, create backups, update certificates etc).
RUN apt install cron logrotate p7zip git build-essential
RUN git clone --depth=1 https://github.com/hoytech/vmtouch.git && \
	cd vmtouch && make && make install && \
	cd .. && rm -rf vmtouch
COPY src/cron.daily "/etc/cron.daily/${HOSTNAME}"
COPY src/logrotate "/etc/logrotate.d/${HOSTNAME}"

# nullmailer asks questions, ignore them because we configure it later.
RUN DEBIAN_FRONTEND=noninteractive apt install nullmailer
RUN echo "${HOSTNAME}" > /etc/mailname
RUN rm -rf /etc/nullmailer && \
	ln -sf /var/www/.htsecure/nullmailer /etc/nullmailer

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

#COPY src/fonts.conf "${HOME}/.config/fontconfig/"
#        xvfb fonts-croscore    `# for renderer script` \

# To get a list of Hetzner IP addresses.
RUN apt install bind9-host
COPY src/start.sh /usr/local/bin/start.sh
CMD ["start.sh"]
